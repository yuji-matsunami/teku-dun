import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/location/location_provider.dart';
import '../core/log/jsonl_log_sink.dart';
import '../core/log/session_store.dart';
import '../core/models/location_sample.dart';
import '../core/models/session_meta.dart';
import '../core/models/tracking_event.dart';
import '../device/battery_sampler.dart';
import '../device/device_info_probe.dart';
import '../health/health_steps_reader.dart';
import '../providers/provider_registry.dart';

/// [SessionController.latestStepsSnapshot] がどの区間を覆っているかを表す。
///
/// 開始時と終了時では歩数スナップショットの対象区間が全く違う。
/// 同じラベルで表示すると、当日の累計歩数を「この散歩の歩数」として
/// 比較表へ転記してしまう。表示側は必ずこの値でラベルを切り替えること。
enum StepsSnapshotScope {
  /// 計測開始時点で読んだ「当日0時 〜 計測開始」の累計歩数。
  /// 散歩そのものの歩数ではなく、あくまで開始時点の参考値。
  beforeSession,

  /// 計測終了時に読んだ「計測開始 〜 計測終了」の歩数。
  /// issue #5 の比較表に載せるのはこちら。
  session,
}

/// アプリ全体の状態を保持する [ChangeNotifier]。
///
/// issue #5 の目的 (画面ロック中も位置情報・歩数の収集が続くかを検証し、
/// flutter_background_geolocation と tracelet を同じ端末で比較する) を
/// 達成するために必要な、計測セッションのライフサイクル管理・ログ書き込み・
/// 権限リクエスト・端末情報収集をすべてここに集約する。
///
/// Riverpod 等の状態管理パッケージは使わず、プレーンな [ChangeNotifier] と
/// `ListenableBuilder` / `AnimatedBuilder` の組み合わせのみで UI と接続する。
class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  SessionController({
    HealthStepsReader? healthStepsReader,
    BatterySampler? batterySampler,
    DeviceInfoProbe? deviceInfoProbe,
  }) : _healthReader = healthStepsReader ?? HealthStepsReader(),
       _batterySampler = batterySampler ?? BatterySampler(),
       _deviceInfoProbe = deviceInfoProbe ?? DeviceInfoProbe() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// メモリを使い果たさないよう、直近サンプルはこの件数だけ保持する。
  /// 完全な記録は JSONL ファイルに逐次書き込まれているため、
  /// UI 表示用のこの一覧はあくまで「直近の様子見」用途で十分。
  static const int _maxRecentSamples = 200;

  /// 状態メッセージも同様に無限に溜め込まないよう上限を設ける。
  static const int _maxMessages = 20;

  final HealthStepsReader _healthReader;
  final BatterySampler _batterySampler;
  final DeviceInfoProbe _deviceInfoProbe;

  SessionStore? _store;
  LocationProvider? _provider;
  JsonlLogSink? _sink;

  StreamSubscription<LocationSample>? _samplesSub;
  StreamSubscription<TrackingEvent>? _eventsSub;
  StreamSubscription<TrackingEvent>? _batterySub;
  Timer? _tickTimer;

  bool _initialized = false;

  /// 初期化 (init) が完了したかどうか。
  bool get isInitialized => _initialized;

  /// 保存済みセッションの一覧・詳細を読むために UI 層 (sessions_page.dart) から
  /// 参照する。書き込み用の [JsonlLogSink] は本クラスが管理するため、
  /// ここでは読み取り専用の用途を想定している。
  SessionStore? get store => _store;

  /// 選択中のプロバイダ種別。
  ProviderKind selectedProviderKind = ProviderKind.fbg;

  /// 現在計測中かどうか。
  bool isRunning = false;

  /// 現在のセッションのメタ情報。
  SessionMeta? currentSession;

  /// 端末情報のスナップショット。
  Map<String, dynamic> deviceInfo = const <String, dynamic>{};

  /// 直近の権限リクエスト結果 (位置情報プロバイダ側)。
  PermissionOutcome? latestPermissionOutcome;

  /// Health Connect の利用可否。
  HealthAvailability? healthAvailability;

  /// Health Connect の歩数権限リクエスト結果。
  HealthPermissionResult? latestHealthPermissionResult;

  /// 直近の歩数スナップショット。
  StepsSnapshot? latestStepsSnapshot;

  /// [latestStepsSnapshot] がどの区間の歩数かを表す。
  ///
  /// 開始時と終了時ではスナップショットが覆う区間が全く違うため、
  /// 同じラベルで表示すると「当日の累計歩数」を「散歩の歩数」として
  /// 転記してしまう。表示側は必ずこの値でラベルを切り替えること。
  StepsSnapshotScope? latestStepsSnapshotScope;

  /// プロバイダの停止に失敗したまま解決していない場合の警告メッセージ。
  ///
  /// 停止できていない = Android 側の常駐フォアグラウンドサービスが
  /// 動き続けているということで、次の計測の電池消費を丸ごと汚染する。
  /// 流れて消えるメッセージ一覧とは別に状態として保持し、
  /// UI に常時警告バナーを出すために使う。
  String? providerStopFailureMessage;

  /// 直近セッション終了時の、プラグイン内部DBと自前ログの突き合わせ結果。
  ///
  /// 自前ログが途中で途切れていた場合に、
  /// 「ライブラリが計測を止めた」のか「アプリの Dart 側だけが落ちて
  /// ネイティブは記録し続けていた」のかを切り分ける材料になる。
  PluginRecordStats? latestPluginRecordStats;

  /// 直近のバッテリー残量。
  BatteryReading? latestBattery;

  /// 直近サンプル (最大 [_maxRecentSamples] 件)。
  final List<LocationSample> recentSamples = <LocationSample>[];

  /// 直近の状態・エラーメッセージ (最大 [_maxMessages] 件、新しいものが末尾)。
  final List<String> messages = <String>[];

  /// セッション内で受信したサンプル総数。
  int sampleCount = 0;

  /// セッション開始時刻 (UTC)。表示用の経過時間の起点。
  DateTime? sessionStartedAt;

  /// 直近のサンプル (位置情報) を受信した時刻 (UTC)。
  DateTime? lastFixAt;

  /// 直近のサンプル。lat/lng/accuracy/speed/isMoving/activity の表示に使う。
  LocationSample? get latestSample =>
      recentSamples.isEmpty ? null : recentSamples.last;

  /// セッション開始からの経過時間。未開始なら `null`。
  Duration? get elapsed {
    final start = sessionStartedAt;
    if (start == null) return null;
    final end = isRunning
        ? DateTime.now().toUtc()
        : (currentSession?.endedAt ?? DateTime.now().toUtc());
    return end.difference(start);
  }

  /// 最後に位置情報を受信してから経過した時間。
  /// これが伸び続ける場合、バックグラウンドでの計測が止まっている疑いが強い。
  Duration? get lastFixAge {
    final last = lastFixAt;
    if (last == null) return null;
    return DateTime.now().toUtc().difference(last);
  }

  void _pushMessage(String message) {
    messages.add(message);
    if (messages.length > _maxMessages) {
      messages.removeAt(0);
    }
  }

  /// 後始末の 1 ステップを実行する。
  ///
  /// 失敗しても例外を外へ投げず、メッセージだけ残して次のステップへ進む。
  /// 「1 か所の失敗で残りの後始末が丸ごと飛ぶ」ことを防ぐためのもの。
  Future<void> _safely(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _pushMessage('$label に失敗しました: $e');
    }
  }

  /// プロバイダの停止に失敗したことを、UI から見逃せない形で記録する。
  void _reportProviderStopFailure(Object error) {
    providerStopFailureMessage = 'プロバイダを停止できませんでした: $error\n'
        '常駐サービスが動き続けている可能性があります。'
        '停止をやり直すまで次の計測を開始しないでください '
        '(電池消費の比較が無効になります)。';
    _pushMessage('プロバイダの停止に失敗しました: $error');
  }

  /// [selectedProviderKind] に対応する [LocationProvider] を用意する
  /// (既に用意済みなら何もしない)。
  Future<void> _ensureProvider() async {
    if (_provider != null) return;
    final provider = createLocationProvider(selectedProviderKind);
    await provider.initialize();
    _provider = provider;
  }

  /// アプリ起動時に一度だけ呼び出す初期化処理。
  ///
  /// [SessionStore] のディレクトリ解決・端末情報の収集・
  /// Health Connect の利用可否確認・バッテリー残量の読み取りを行う。
  /// いずれかが失敗しても例外は外に投げず、状態メッセージとして残す。
  Future<void> init() async {
    if (_initialized) return;
    try {
      _store = await SessionStore.openDefault(
        resolveDir: getApplicationDocumentsDirectory,
      );
      deviceInfo = await _deviceInfoProbe.collect();
      healthAvailability = await _healthReader.checkAvailability();
      latestBattery = await _batterySampler.read();
      await _ensureProvider();
      _initialized = true;
    } catch (e) {
      _pushMessage('初期化に失敗しました: $e');
    } finally {
      notifyListeners();
    }
  }

  /// 位置情報プロバイダおよび Health Connect の権限をリクエストする。
  ///
  /// issue #5 では「許可された場合」だけでなく「拒否された場合」の挙動も
  /// 確認する必要があるため、結果は常に状態として保持し UI に反映する
  /// (拒否は隠すべきエラーではなく、検証対象の挙動そのものである)。
  Future<void> requestAllPermissions() async {
    try {
      await _ensureProvider();
      final provider = _provider;
      if (provider != null) {
        // プロバイダ自身が requestPermissions 内部で
        // TrackingEventKind.permissionResult イベントを events ストリームに
        // 発行する。セッション実行中はそのストリームを購読済みのため、
        // 位置情報側の権限結果は自動的にログへ追記される。
        latestPermissionOutcome = await provider.requestPermissions();
      }

      final healthResult = await _healthReader.requestPermission();
      latestHealthPermissionResult = healthResult;
      healthAvailability = await _healthReader.checkAvailability();

      final sink = _sink;
      if (isRunning && sink != null) {
        await sink.append(
          TrackingEvent(
            at: DateTime.now().toUtc(),
            kind: TrackingEventKind.permissionResult,
            data: <String, dynamic>{
              'source': 'healthConnect',
              ...healthResult.toJson(),
            },
          ).toJson(),
        );
      }
      _pushMessage('権限の確認結果を更新しました。');
    } catch (e) {
      _pushMessage('権限リクエストに失敗しました: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Health Connect アプリのインストール導線を開く。
  Future<void> openHealthConnectInstall() async {
    try {
      await _healthReader.openHealthConnectInstall();
    } catch (e) {
      _pushMessage('Health Connect のインストール画面を開けませんでした: $e');
      notifyListeners();
    }
  }

  /// 計測セッションを開始する。
  Future<void> startSession() async {
    if (isRunning) {
      _pushMessage('既に計測中です。');
      notifyListeners();
      return;
    }
    if (providerStopFailureMessage != null) {
      _pushMessage('前のプロバイダを停止できていないため開始できません。先に停止をやり直してください。');
      notifyListeners();
      return;
    }
    final store = _store;
    if (store == null) {
      _pushMessage('初期化が完了していないため開始できません。');
      notifyListeners();
      return;
    }

    try {
      await _ensureProvider();
      final provider = _provider!;

      final battery = await _batterySampler.read();
      latestBattery = battery;

      final meta = await store.createSession(
        providerId: provider.id,
        deviceInfo: deviceInfo,
        providerConfig: provider.configSummary,
        batteryAtStart: battery.levelPercent,
      );
      currentSession = meta;

      final sink = store.sinkFor(meta.id);
      _sink = sink;

      recentSamples.clear();
      sampleCount = 0;
      lastFixAt = null;
      sessionStartedAt = meta.startedAt;

      _samplesSub = provider.samples.listen((sample) {
        sampleCount += 1;
        lastFixAt = DateTime.now().toUtc();
        recentSamples.add(sample);
        if (recentSamples.length > _maxRecentSamples) {
          recentSamples.removeAt(0);
        }
        notifyListeners();
        unawaited(
          sink.append(sample.toJson()).catchError((Object e) {
            _pushMessage('サンプルの書き込みに失敗しました: $e');
            notifyListeners();
          }),
        );
      });

      _eventsSub = provider.events.listen((event) {
        notifyListeners();
        unawaited(
          sink.append(event.toJson()).catchError((Object e) {
            _pushMessage('イベントの書き込みに失敗しました: $e');
            notifyListeners();
          }),
        );
      });

      _batterySub = _batterySampler.periodic().listen((event) {
        final levelPercent = event.data['levelPercent'] as int?;
        final isCharging = event.data['isCharging'] as bool?;
        latestBattery = BatteryReading(
          levelPercent: levelPercent,
          isCharging: isCharging,
          at: event.at,
        );
        notifyListeners();
        unawaited(
          sink.append(event.toJson()).catchError((Object e) {
            _pushMessage('バッテリー記録の書き込みに失敗しました: $e');
            notifyListeners();
          }),
        );
      });

      await sink.append(
        TrackingEvent(
          at: meta.startedAt,
          kind: TrackingEventKind.sessionStart,
          data: <String, dynamic>{'providerId': provider.id},
        ).toJson(),
      );

      // 開始時点のスナップショット: 「今日この瞬間までの歩数」を参考値として記録する
      // (セッション区間そのものの歩数は終了時にまとめて記録する)。
      final dayStart = DateTime(
        meta.startedAt.toLocal().year,
        meta.startedAt.toLocal().month,
        meta.startedAt.toLocal().day,
      );
      final startSnapshot = await _healthReader.readSteps(
        start: dayStart,
        end: meta.startedAt,
      );
      latestStepsSnapshot = startSnapshot;
      latestStepsSnapshotScope = StepsSnapshotScope.beforeSession;
      await sink.append(
        TrackingEvent(
          at: startSnapshot.end,
          kind: TrackingEventKind.healthSnapshot,
          data: <String, dynamic>{'phase': 'start', ...startSnapshot.toJson()},
        ).toJson(),
      );

      // ヘッドレス isolate はアプリのメモリを共有しないため、
      // 対象セッションをディスク経由でしか知りえない。
      // provider.start() より前に書いておく。
      await _store?.writeActiveSessionId(meta.id);

      isRunning = true;
      _startTicker();
      await provider.start();
      _pushMessage('${labelOf(selectedProviderKind)} で計測を開始しました。');
    } catch (e) {
      _pushMessage('計測開始に失敗しました: $e');
      await _rollbackFailedStart();
    } finally {
      notifyListeners();
    }
  }

  /// [startSession] が途中で失敗した場合の後始末。
  ///
  /// `provider.start()` がネイティブサービス起動後に失敗した場合、
  /// ここで stop() を呼ばないとサービスだけが動き続け、
  /// アプリからは `isTracking == false` に見える状態になる。
  /// 各ステップは個別に保護し、1 つ失敗しても残りを必ず実行する。
  Future<void> _rollbackFailedStart() async {
    isRunning = false;
    _stopTicker();

    // 計測中フラグを消す。消し忘れると、開始に失敗したセッションを
    // 指したままヘッドレスタスクが記録を追記し続け、
    // 一度も開始されなかったセッションのログが汚れる。
    await _safely('計測中フラグのクリア', () async {
      await _store?.writeActiveSessionId(null);
    });

    final provider = _provider;
    if (provider != null) {
      try {
        await provider.stop();
      } catch (e) {
        _reportProviderStopFailure(e);
      }
    }

    await _safely('サンプル購読の解除', () async {
      await _samplesSub?.cancel();
    });
    await _safely('イベント購読の解除', () async {
      await _eventsSub?.cancel();
    });
    await _safely('バッテリー購読の解除', () async {
      await _batterySub?.cancel();
    });
    _samplesSub = null;
    _eventsSub = null;
    _batterySub = null;
    await _safely('ログファイルのクローズ', () async {
      await _sink?.close();
    });
    _sink = null;
  }

  /// 計測セッションを終了する。
  ///
  /// __途中で失敗しても、必ず終了状態を保存して後片付けを完了させる。__
  ///
  /// 以前は全処理が1つの try に入っていたため、たとえば `provider.stop()` が
  /// 失敗しただけで meta.json の endedAt / batteryAtEnd が未設定のまま残り、
  /// 15分歩いた実測の電池比較が丸ごと失われた。
  /// そのため各ステップを個別に保護し、最優先である「終了時刻と電池残量の
  /// 永続化」を先に済ませる。
  Future<void> stopSession() async {
    if (!isRunning) {
      _pushMessage('計測は開始されていません。');
      notifyListeners();
      return;
    }

    final provider = _provider;
    final sink = _sink;
    final meta = currentSession;
    final endedAt = DateTime.now().toUtc();

    try {
      // 0. 計測中フラグをディスクから消す。
      //    消し忘れると、計測していない時間帯にヘッドレスタスクが拾った
      //    イベントが、このセッションのログへ混入する。
      try {
        await _store?.writeActiveSessionId(null);
      } catch (e) {
        _pushMessage('計測中フラグのクリアに失敗しました: $e');
      }

      // 1. まず計測を止める。ここで止め損なうと次の計測の電池消費が汚れる。
      if (provider != null) {
        try {
          await provider.stop();
          providerStopFailureMessage = null;
        } catch (e) {
          providerStopFailureMessage =
              '${provider.displayName} の停止に失敗しました。'
              'Android の常駐サービスが動き続けている可能性があります。'
              'このまま次の計測に進むと電池消費の比較が汚れます。'
              'アプリを再起動してください。詳細: $e';
          _pushMessage('プロバイダの停止に失敗しました: $e');
        }
      }

      // 2. 終了時刻と電池残量を永続化する。ここが最優先。
      //    これを取り逃すと電池消費の比較ができなくなる。
      BatteryReading? battery;
      try {
        battery = await _batterySampler.read();
        latestBattery = battery;
      } catch (e) {
        _pushMessage('電池残量の取得に失敗しました: $e');
      }

      if (meta != null) {
        try {
          final updatedMeta = meta.copyWith(
            endedAt: endedAt,
            batteryAtEnd: battery?.levelPercent,
          );
          await _store?.updateMeta(updatedMeta);
          currentSession = updatedMeta;
        } catch (e) {
          _pushMessage('セッション情報の保存に失敗しました: $e');
        }
      }

      // 3. プラグイン内部DBと自前ログの突き合わせ。
      //    ログが途切れていた場合に「ライブラリが止まった」のか
      //    「アプリだけが落ちた」のかを切り分ける材料になる。
      if (provider != null && sink != null && meta != null) {
        try {
          final stats = await provider.readPluginRecords(
            from: meta.startedAt,
            to: endedAt,
          );
          latestPluginRecordStats = stats;
          await sink.append(
            TrackingEvent(
              at: endedAt,
              kind: TrackingEventKind.pluginRecordStats,
              data: <String, dynamic>{
                'providerId': provider.id,
                'jsonlSampleCount': sampleCount,
                ...stats.toJson(),
              },
            ).toJson(),
          );
        } catch (e) {
          _pushMessage('プラグイン記録の読み出しに失敗しました: $e');
        }
      }

      // 4. セッション区間の歩数を記録する。
      if (sink != null && meta != null) {
        try {
          final endSnapshot = await _healthReader.readSteps(
            start: meta.startedAt,
            end: endedAt,
          );
          latestStepsSnapshot = endSnapshot;
          latestStepsSnapshotScope = StepsSnapshotScope.session;
          await sink.append(
            TrackingEvent(
              at: endSnapshot.end,
              kind: TrackingEventKind.healthSnapshot,
              data: <String, dynamic>{'phase': 'end', ...endSnapshot.toJson()},
            ).toJson(),
          );
        } catch (e) {
          _pushMessage('歩数の取得に失敗しました: $e');
        }
      }

      // 5. セッション終了イベントを記録する。
      if (sink != null) {
        try {
          await sink.append(
            TrackingEvent(
              at: endedAt,
              kind: TrackingEventKind.sessionEnd,
              data: <String, dynamic>{
                'providerId': provider?.id ?? meta?.providerId,
              },
            ).toJson(),
          );
        } catch (e) {
          _pushMessage('終了イベントの記録に失敗しました: $e');
        }
      }

      _pushMessage('計測を停止しました。');
    } finally {
      // 6. 後片付けは何があっても実行する。
      //    ここを飛ばすと isRunning が true のまま固まり、
      //    ログの書き込み先も開いたままになる。
      try {
        await _samplesSub?.cancel();
        await _eventsSub?.cancel();
        await _batterySub?.cancel();
      } catch (_) {
        // 購読解除の失敗は握りつぶす。ここで止まると片付けが進まない。
      }
      _samplesSub = null;
      _eventsSub = null;
      _batterySub = null;
      _stopTicker();

      try {
        await sink?.close();
      } catch (e) {
        _pushMessage('ログファイルのクローズに失敗しました: $e');
      }
      _sink = null;

      isRunning = false;
      notifyListeners();
    }
  }

  /// プロバイダを切り替える。
  ///
  /// __重要__: 両プロバイダとも Android 上では常駐通知付きフォアグラウンド
  /// サービスとして動作するため、古いプロバイダを stop → dispose してから
  /// でないと次のプロバイダを起動してはいけない (バッテリー消費が二重に
  /// かかり、比較実験そのものが成立しなくなる)。
  Future<void> switchProvider(ProviderKind kind) async {
    if (isRunning) {
      _pushMessage('計測中はプロバイダを切り替えられません。先に停止してください。');
      notifyListeners();
      return;
    }
    if (kind == selectedProviderKind && _provider != null) {
      return;
    }

    final old = _provider;
    try {
      // __参照を先に手放してはならない。__
      // 停止に失敗した旧プロバイダの参照を失うと、Android 側の常駐
      // フォアグラウンドサービスを二度と止められなくなる。その状態で
      // もう一方を起動すると、2つのサービスが同時に走って電池消費が
      // 倍になり、比較そのものが壊れる。
      // 停止と破棄が確実に終わってから参照を差し替える。
      if (old != null) {
        await old.stop();
        await old.dispose();
        _provider = null;
      }
      providerStopFailureMessage = null;

      selectedProviderKind = kind;
      latestPermissionOutcome = null;

      final provider = createLocationProvider(kind);
      await provider.initialize();
      _provider = provider;
      _pushMessage('プロバイダを ${labelOf(kind)} に切り替えました。');
    } catch (e) {
      // 旧プロバイダを停止できていない可能性がある。参照は保持したままにし、
      // 再試行できる状態を残す。流れて消えるメッセージ一覧だけでなく、
      // 画面に出し続ける警告としても保持する。
      if (_provider == old && old != null) {
        providerStopFailureMessage =
            '${old.displayName} の停止に失敗した可能性があります。'
            'このまま計測すると電池消費の比較が汚れます。'
            'もう一度切り替えるか、アプリを再起動してください。詳細: $e';
      }
      _pushMessage('プロバイダの切り替えに失敗しました: $e');
    } finally {
      notifyListeners();
    }
  }

  void _startTicker() {
    _tickTimer?.cancel();
    // 経過時間・最終取得からの経過秒数は DateTime.now() からの計算式なので、
    // 新しいサンプルが来ない間も画面を更新し続けるために 1 秒おきに再描画する。
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  void _stopTicker() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 画面ロック・バックグラウンド遷移をログへ残すことで、後から
    // 「バックグラウンドや画面ロック中もサンプルが届き続けていたか」を
    // 位置情報サンプルと突き合わせて検証できるようにする。
    final sink = _sink;
    if (!isRunning || sink == null) return;
    unawaited(
      sink
          .append(
            TrackingEvent(
              at: DateTime.now().toUtc(),
              kind: TrackingEventKind.appLifecycle,
              data: <String, dynamic>{'state': state.name},
            ).toJson(),
          )
          .catchError((Object e) {
            _pushMessage('ライフサイクルイベントの記録に失敗しました: $e');
            notifyListeners();
          }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTicker();
    _samplesSub?.cancel();
    _eventsSub?.cancel();
    _batterySub?.cancel();
    _sink?.close();
    _provider?.dispose();
    super.dispose();
  }
}

/// `1:23:45` 形式で [Duration] を表示するための共通ヘルパー。
/// UI 層 (home_page.dart / sessions_page.dart) から共通で利用する。
String formatDuration(Duration d) {
  final abs = d.abs();
  final h = abs.inHours;
  final m = abs.inMinutes.remainder(60);
  final s = abs.inSeconds.remainder(60);
  final sign = d.isNegative ? '-' : '';
  return '$sign$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// `2026/08/22 09:00:00` 形式でローカル時刻を表示するための共通ヘルパー。
String formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
