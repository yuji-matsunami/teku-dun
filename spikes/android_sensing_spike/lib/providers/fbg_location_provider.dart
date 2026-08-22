import 'dart:async';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:permission_handler/permission_handler.dart' as ph;

import '../core/location/location_provider.dart';
import '../core/models/location_sample.dart';
import '../core/models/tracking_event.dart';
import 'compare_config.dart';

/// プラグイン DB から一度に取得する最大件数。
/// 全件取得は fbg 公式ドキュメントでメモリ枯渇の危険が警告されている。
/// 10〜15 分の歩行 1 回分には十分に足りる件数を上限とする。
const int _pluginRecordFetchLimit = 5000;

/// プラグインが返すタイムスタンプ (ISO-8601 文字列、または epoch ミリ秒) を
/// UTC の [DateTime] に変換する。解釈できない場合は null。
DateTime? _parsePluginTimestamp(Object? raw) {
  if (raw is String) {
    return DateTime.tryParse(raw)?.toUtc();
  }
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  return null;
}

/// `flutter_background_geolocation` (5.5.0) を使った [LocationProvider] 実装。
///
/// 実装にあたっては pub-cache 上のインストール済みソース
/// (`flutter_background_geolocation-5.5.0/lib/models/*.dart`) を確認済み。
/// v5 系では `foregroundService` オプションは廃止されており、Android では
/// 常時フォアグラウンドサービスとして動作する (設定不可)。
class FbgLocationProvider implements LocationProvider {
  FbgLocationProvider();

  @override
  String get id => 'fbg';

  @override
  String get displayName => 'flutter_background_geolocation';

  bool _initialized = false;
  bool _isTracking = false;

  int _seq = 0;

  bg.Subscription? _locationSub;
  bg.Subscription? _motionChangeSub;
  bg.Subscription? _activityChangeSub;
  bg.Subscription? _providerChangeSub;

  final StreamController<LocationSample> _samplesController =
      StreamController<LocationSample>.broadcast();
  final StreamController<TrackingEvent> _eventsController =
      StreamController<TrackingEvent>.broadcast();

  @override
  Stream<LocationSample> get samples => _samplesController.stream;

  @override
  Stream<TrackingEvent> get events => _eventsController.stream;

  @override
  bool get isTracking => _isTracking;

  /// fbg の実効設定。
  ///
  /// `locationUpdateInterval` は「設定はしているが効いていない」。
  /// fbg 公式ドキュメントに
  /// 「`locationUpdateInterval` を使うには `distanceFilter: 0` にする必要がある。
  /// `distanceFilter` が `locationUpdateInterval` を上書きするからだ」
  /// と明記されている。本スパイクは両プロバイダで `distanceFilter: 10m` を
  /// 揃えているため、fbg 側は純粋に移動距離駆動で発火する。
  ///
  /// ここで 5000ms を「有効な設定」として記録すると、画面の
  /// 「プロバイダ設定」欄を見た検証者が「どちらも 5 秒間隔の設定」と読み、
  /// 取得間隔の差をライブラリの性能差だと取り違える。
  /// そのため無効である旨を明示して記録する。
  @override
  Map<String, dynamic> get configSummary => <String, dynamic>{
    'providerId': id,
    'accuracy': 'high',
    'distanceFilterMeters': CompareConfig.distanceFilterMeters,
    'locationUpdateIntervalMs': CompareConfig.locationUpdateIntervalMs,
    'locationUpdateIntervalEffective': false,
    'locationUpdateIntervalNote':
        'distanceFilter > 0 のため fbg では無視される (公式仕様)。'
        '実際の発火は移動距離駆動。',
    'stopOnTerminate': CompareConfig.stopOnTerminate,
    'startOnBoot': CompareConfig.startOnBoot,
  };

  @override
  Future<void> initialize() async {
    // ready() は複数回呼んでも安全 (再設定として扱われる) だが、
    // 呼び出し側の意図 (「1 度だけ初期化する」) を明確にするため
    // 自前でも冪等性を保証しておく。
    if (_initialized) {
      return;
    }

    _registerSubscriptions();

    await bg.BackgroundGeolocation.ready(
      bg.Config(
        geolocation: bg.GeoConfig(
          desiredAccuracy: bg.DesiredAccuracy.high,
          distanceFilter: CompareConfig.distanceFilterMeters,
          locationUpdateInterval: CompareConfig.locationUpdateIntervalMs,
          stationaryRadius: 25,
          stopTimeout: 5,
        ),
        app: bg.AppConfig(
          stopOnTerminate: CompareConfig.stopOnTerminate,
          startOnBoot: CompareConfig.startOnBoot,
          notification: bg.Notification(
            title: '位置情報計測中 (fbg)',
            text: 'flutter_background_geolocation で計測しています。',
          ),
        ),
        logger: bg.LoggerConfig(
          debug: true,
          logLevel: bg.LogLevel.verbose,
        ),
      ),
    );

    _initialized = true;
  }

  void _registerSubscriptions() {
    _locationSub = bg.BackgroundGeolocation.onLocation(
      _handleLocation,
      _handleLocationError,
    );
    _motionChangeSub = bg.BackgroundGeolocation.onMotionChange(
      _handleMotionChange,
    );
    _activityChangeSub = bg.BackgroundGeolocation.onActivityChange(
      _handleActivityChange,
    );
    _providerChangeSub = bg.BackgroundGeolocation.onProviderChange(
      _handleProviderChange,
    );
  }

  /// fbg が「使い捨てサンプル」として配信した位置の累計件数。
  ///
  /// tracelet には対応する概念が無いため、この件数だけ fbg のサンプル数が
  /// 水増しされる。除外した件数自体も比較の材料になるので記録しておく。
  int _skippedSampleCount = 0;

  /// 除外した使い捨てサンプルの累計件数。
  int get skippedSampleCount => _skippedSampleCount;

  void _handleLocation(bg.Location location) {
    // fbg は onMotionChange / getCurrentPosition のたびに複数の位置を
    // 要求し、そのすべてを onLocation へ配信する。公式ドキュメントは
    // これらを「自前 DB へ保存せず、サーバへ送るなら無視すべきもの」と
    // 明記している (Location.sample フラグで判別できる)。
    //
    // tracelet の Location にはこれに相当するフィールドが無く、同種の
    // バーストも発生しない。そのまま数えると停止→移動の遷移ごとに
    // fbg 側だけサンプル数が増え、取得間隔の中央値も 0 方向へ引っ張られ、
    // 「fbg のほうが密に取れている」という誤った結論になる。
    //
    // したがって LocationSample としては採用しない。ただし黙って捨てると
    // fbg のバースト挙動そのものが見えなくなるため、件数をイベントとして
    // ログへ残す。
    if (location.sample) {
      _skippedSampleCount++;
      _emitEvent(TrackingEventKind.providerError, <String, dynamic>{
        'source': 'onLocation',
        'severity': 'info',
        'reason': 'fbgSampleLocationSkipped',
        'message':
            'fbg の使い捨てサンプル (Location.sample == true) を集計対象から除外した。',
        'skippedSampleCount': _skippedSampleCount,
      });
      return;
    }
    _emitSample(location);
  }

  void _handleLocationError(bg.LocationError error) {
    _emitEvent(
      TrackingEventKind.providerError,
      <String, dynamic>{
        'source': 'onLocation',
        'code': error.code,
        'message': error.message,
      },
    );
  }

  void _handleMotionChange(bg.Location location) {
    _emitEvent(
      TrackingEventKind.motionChange,
      <String, dynamic>{'isMoving': location.isMoving},
    );
  }

  void _handleActivityChange(bg.ActivityChangeEvent event) {
    _emitEvent(
      TrackingEventKind.activityChange,
      <String, dynamic>{
        'activity': event.activity,
        'confidence': event.confidence,
      },
    );
  }

  void _handleProviderChange(bg.ProviderChangeEvent event) {
    _emitEvent(
      TrackingEventKind.providerChange,
      <String, dynamic>{
        'enabled': event.enabled,
        'status': event.status,
        'network': event.network,
        'gps': event.gps,
      },
    );
  }

  void _emitSample(bg.Location location) {
    final receivedAt = DateTime.now().toUtc();
    DateTime recordedAt;
    try {
      // timestamp は既定 (PersistenceConfig.timestampFormat == 'iso') では
      // ISO-8601 の String。念のため int (epoch ms) のケースにも対応する。
      final dynamic ts = location.timestamp;
      if (ts is String) {
        recordedAt = DateTime.parse(ts).toUtc();
      } else if (ts is int) {
        recordedAt = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
      } else {
        throw FormatException('unsupported timestamp type: ${ts.runtimeType}');
      }
    } catch (e) {
      recordedAt = receivedAt;
      _emitEvent(
        TrackingEventKind.providerError,
        <String, dynamic>{
          'source': 'timestampParse',
          'rawTimestamp': location.timestamp?.toString(),
          'error': e.toString(),
        },
      );
    }

    // battery.level は 0.0-1.0 の割合。0-100 の整数パーセントへ正規化する。
    // 値が取得できない場合 (ダミーペイロードなど) は -1.0 が入るため null 扱いにする。
    final rawLevel = location.battery.level;
    final batteryLevelPercent =
        rawLevel < 0 ? null : (rawLevel * 100).round();

    _seq += 1;
    final sample = LocationSample(
      seq: _seq,
      providerId: id,
      recordedAt: recordedAt,
      receivedAt: receivedAt,
      latitude: location.coords.latitude,
      longitude: location.coords.longitude,
      accuracy: location.coords.accuracy,
      altitude: location.coords.altitude,
      speed: location.coords.speed,
      heading: location.coords.heading,
      isMoving: location.isMoving,
      activity: location.activity.type,
      activityConfidence: location.activity.confidence,
      odometer: location.odometer,
      batteryLevelPercent: batteryLevelPercent,
      batteryCharging: location.battery.isCharging,
      isMock: location.mock,
    );

    _samplesController.add(sample);
  }

  void _emitEvent(String kind, Map<String, dynamic> data) {
    _eventsController.add(
      TrackingEvent(at: DateTime.now().toUtc(), kind: kind, data: data),
    );
  }

  @override
  Future<PermissionOutcome> requestPermissions() async {
    // Android 10+ では「使用中のみ許可」を先に確定させてから「常に許可」を
    // 求めないと、OS がダイアログ自体を出してくれない場合がある。
    final whenInUseStatus = await ph.Permission.locationWhenInUse.request();
    ph.PermissionStatus alwaysStatus = whenInUseStatus;
    if (whenInUseStatus.isGranted) {
      alwaysStatus = await ph.Permission.locationAlways.request();
    }
    final activityStatus = await ph.Permission.activityRecognition.request();
    final notificationStatus = await ph.Permission.notification.request();

    // fbg 自身にも権限リクエストを行わせ、SDK 側が実際にどう認識したかを
    // status (AUTHORIZATION_STATUS_*) として記録する。
    final fbgStatus = await bg.BackgroundGeolocation.requestPermission();

    final outcome = PermissionOutcome(
      fineLocationGranted: whenInUseStatus.isGranted,
      backgroundLocationGranted: alwaysStatus.isGranted,
      activityRecognitionGranted: activityStatus.isGranted,
      notificationsGranted: notificationStatus.isGranted,
      rawStatus:
          'fbg=$fbgStatus,whenInUse=$whenInUseStatus,always=$alwaysStatus,'
          'activity=$activityStatus,notification=$notificationStatus',
    );

    _emitEvent(
      TrackingEventKind.permissionResult,
      <String, dynamic>{...outcome.toJson(), 'providerId': id},
    );

    return outcome;
  }

  @override
  Future<void> start() async {
    if (!_initialized) {
      await initialize();
    }
    // セッションごとに連番をリセットする。
    _seq = 0;
    await bg.BackgroundGeolocation.start();
    _isTracking = true;
  }

  /// 計測を停止する。
  ///
  /// __重要__: fbg は Android では常時フォアグラウンドサービス
  /// (常駐通知) を伴って動作する。`stop()` を呼び忘れると通知と
  /// バックグラウンド計測が動き続け、もう一方のプロバイダ (tracelet) を
  /// 起動した際にバッテリー消費が二重にかかり比較実験が壊れる。
  /// そのため [stop] は必ず SDK の `stop()` を呼び、フォアグラウンド
  /// サービスと常駐通知を確実に停止させる。
  /// __Dart 側のフラグで早期 return してはならない。__
  ///
  /// 本プロバイダは `stopOnTerminate: false` で動作する。fbg の公式ドキュメント
  /// にあるとおり、Android ではアプリが終了させられてもネイティブの
  /// バックグラウンドサービスはヘッドレスで動き続ける。
  /// つまりアプリを再起動した直後の [_isTracking] は false だが、
  /// 実際にはサービスが生きている、という状態が起こりうる。
  ///
  /// ここで `_isTracking` を見て早期 return すると、その生き残った
  /// サービスを止められないまま、もう一方のプロバイダを起動してしまう。
  /// フォアグラウンドサービスが 2 つ走れば電池消費はおよそ倍になり、
  /// $399 の判断が乗っている電池比較そのものが壊れる。
  ///
  /// したがって状態にかかわらず必ず SDK の `stop()` を呼ぶ。
  /// 停止済みの状態で呼んでも安全である。
  @override
  Future<void> stop() async {
    try {
      await bg.BackgroundGeolocation.stop();
    } finally {
      _isTracking = false;
    }
  }

  /// fbg が自前の SQLite に永続化した記録を読み出す。
  ///
  /// __注意__: fbg はモーション変化時に発生する使い捨てサンプル
  /// (`Location.sample == true`) を自前 DB へ保存しない。
  /// そのため本メソッドが返す件数は、JSONL ログのサンプル件数と
  /// 元々一致しない。差分の解釈には注意すること。
  ///
  /// fbg の `LocationQuery` は時刻範囲での絞り込みに対応していないため、
  /// 新しい順に一定件数を取得し、Dart 側で期間を絞る。
  /// 全件取得は公式ドキュメントでメモリ枯渇の危険があると警告されている。
  ///
  /// 破壊的な `destroyLocations()` は決して呼ばない。件数を数えやすくする
  /// ために DB を消す実装にすると、取り違えた場合に実測データそのものを失う。
  @override
  Future<PluginRecordStats> readPluginRecords({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final totalCount = await bg.BackgroundGeolocation.count;
      final records = await bg.BackgroundGeolocation.getLocations(
        bg.LocationQuery(
          limit: _pluginRecordFetchLimit,
          order: bg.LocationQuery.ORDER_DESC,
        ),
      );

      final timestamps = <DateTime>[];
      for (final record in records) {
        if (record is! Map) continue;
        final raw = record['timestamp'];
        final parsed = _parsePluginTimestamp(raw);
        if (parsed == null) continue;
        if (parsed.isBefore(from) || parsed.isAfter(to)) continue;
        timestamps.add(parsed);
      }
      timestamps.sort();

      return PluginRecordStats(
        supported: true,
        totalCount: totalCount,
        countInWindow: timestamps.length,
        firstAt: timestamps.isEmpty ? null : timestamps.first,
        lastAt: timestamps.isEmpty ? null : timestamps.last,
      );
    } catch (e) {
      return PluginRecordStats(supported: true, error: e.toString());
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _locationSub?.remove();
    await _motionChangeSub?.remove();
    await _activityChangeSub?.remove();
    await _providerChangeSub?.remove();
    _locationSub = null;
    _motionChangeSub = null;
    _activityChangeSub = null;
    _providerChangeSub = null;
    await _samplesController.close();
    await _eventsController.close();
  }
}
