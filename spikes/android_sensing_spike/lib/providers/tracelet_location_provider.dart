import 'dart:async';

import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:tracelet/tracelet.dart' as tl;

import '../core/location/location_provider.dart';
import '../core/models/location_sample.dart';
import '../core/models/tracking_event.dart';
import 'compare_config.dart';

/// `tracelet` (3.8.7) を使った [LocationProvider] 実装。
///
/// __実装メモ (インストール済みソースを確認した上での注意点)__:
///
/// * タスク設計時の想定と異なり、`locationUpdateInterval` は `GeoConfig`
///   ではなく __`AndroidConfig`__ に属する
///   (`tracelet-3.8.7/lib/src/models/android_config.dart`)。
/// * 同様に `foregroundService` (通知チャンネル・タイトルなど) も
///   `AppConfig` ではなく __`AndroidConfig.foregroundService`__ に属する。
/// * `onLocation` / `onMotionChange` / `onActivityChange` / `onProviderChange`
///   はいずれも `StreamSubscription<T>` を返す (fbg の `Subscription` 型とは
///   異なり `.remove()` ではなく `.cancel()` を呼ぶ)。ここでは代わりに
///   `Tracelet.locationStream` 等の Stream getter を直接 `listen()` して
///   `StreamSubscription` を保持する方式にした (fbg 実装と対称的な構造にできる)。
/// * `Location.activity` は fbg と異なり non-null (`LocationActivity` の
///   デフォルト値を持つ) で、`type` は `ActivityType` enum、`confidence` は
///   `ActivityConfidence` enum (low/medium/high の 3 段階) であり、
///   fbg のような 0-100 の int ではない。
/// * `Location.battery.level` は fbg と同じく `0.0`-`1.0` (不明時 `-1.0`)
///   であることをソースのドキュメントコメントで確認済み。
/// 「不明」を表すセンチネル値 (負値) を null に均す。
///
/// fbg 実装と同じ規則を適用する。両プロバイダで扱いを揃えないと、
/// 速度や精度の集計値が片方だけ 0 方向へ引っ張られ、比較が崩れる。
double? _sanitize(double? value) {
  if (value == null) return null;
  if (value < 0) return null;
  return value;
}

class TraceletLocationProvider implements LocationProvider {
  TraceletLocationProvider();

  @override
  String get id => 'tracelet';

  @override
  String get displayName => 'tracelet';

  bool _initialized = false;
  bool _isTracking = false;

  int _seq = 0;

  StreamSubscription<tl.Location>? _locationSub;
  StreamSubscription<tl.Location>? _motionChangeSub;
  StreamSubscription<tl.ActivityChangeEvent>? _activityChangeSub;
  StreamSubscription<tl.ProviderChangeEvent>? _providerChangeSub;

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

  @override
  Map<String, dynamic> get configSummary => <String, dynamic>{
        'providerId': id,
        'accuracy': 'high',
        'distanceFilterMeters': CompareConfig.distanceFilterMeters,
        'locationUpdateIntervalMs': CompareConfig.locationUpdateIntervalMs,
        'stopOnTerminate': CompareConfig.stopOnTerminate,
        'startOnBoot': CompareConfig.startOnBoot,
      };

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _registerSubscriptions();

    await tl.Tracelet.ready(
      tl.Config(
        geo: const tl.GeoConfig(
          desiredAccuracy: tl.DesiredAccuracy.high,
          distanceFilter: CompareConfig.distanceFilterMeters,
        ),
        android: const tl.AndroidConfig(
          locationUpdateInterval: CompareConfig.locationUpdateIntervalMs,
          foregroundService: tl.ForegroundServiceConfig(
            channelId: 'tracelet_channel',
            channelName: 'Location Tracking',
            notificationTitle: '位置情報計測中 (tracelet)',
            notificationText: 'tracelet で計測しています。',
          ),
        ),
        app: const tl.AppConfig(
          stopOnTerminate: CompareConfig.stopOnTerminate,
          startOnBoot: CompareConfig.startOnBoot,
        ),
        logger: const tl.LoggerConfig(
          debug: true,
          logLevel: tl.LogLevel.verbose,
        ),
      ),
    );

    _initialized = true;
  }

  void _registerSubscriptions() {
    _locationSub = tl.Tracelet.locationStream.listen(
      _handleLocation,
      onError: (Object error, StackTrace stack) {
        _emitEvent(TrackingEventKind.providerError, <String, dynamic>{
          'source': 'locationStream',
          'error': error.toString(),
        });
      },
    );
    _motionChangeSub = tl.Tracelet.motionChangeStream.listen(
      _handleMotionChange,
      onError: (Object error, StackTrace stack) {
        _emitEvent(TrackingEventKind.providerError, <String, dynamic>{
          'source': 'motionChangeStream',
          'error': error.toString(),
        });
      },
    );
    _activityChangeSub = tl.Tracelet.activityChangeStream.listen(
      _handleActivityChange,
      onError: (Object error, StackTrace stack) {
        _emitEvent(TrackingEventKind.providerError, <String, dynamic>{
          'source': 'activityChangeStream',
          'error': error.toString(),
        });
      },
    );
    _providerChangeSub = tl.Tracelet.providerChangeStream.listen(
      _handleProviderChange,
      onError: (Object error, StackTrace stack) {
        _emitEvent(TrackingEventKind.providerError, <String, dynamic>{
          'source': 'providerChangeStream',
          'error': error.toString(),
        });
      },
    );
  }

  void _handleLocation(tl.Location location) {
    _emitSample(location);
  }

  void _handleMotionChange(tl.Location location) {
    _emitEvent(
      TrackingEventKind.motionChange,
      <String, dynamic>{'isMoving': location.isMoving},
    );
  }

  void _handleActivityChange(tl.ActivityChangeEvent event) {
    _emitEvent(
      TrackingEventKind.activityChange,
      <String, dynamic>{
        'activity': _activityTypeToString(event.activity),
        'confidence': event.confidence.name,
      },
    );
  }

  void _handleProviderChange(tl.ProviderChangeEvent event) {
    _emitEvent(
      TrackingEventKind.providerChange,
      <String, dynamic>{
        'enabled': event.enabled,
        'status': event.status.name,
        'network': event.network,
        'gps': event.gps,
      },
    );
  }

  void _emitSample(tl.Location location) {
    final receivedAt = DateTime.now().toUtc();
    DateTime recordedAt;
    try {
      // timestamp は ISO-8601 String。
      recordedAt = DateTime.parse(location.timestamp).toUtc();
    } catch (e) {
      recordedAt = receivedAt;
      _emitEvent(
        TrackingEventKind.providerError,
        <String, dynamic>{
          'source': 'timestampParse',
          'rawTimestamp': location.timestamp,
          'error': e.toString(),
        },
      );
    }

    // battery.level は fbg と同じく 0.0-1.0 の割合 (インストール済みソースの
    // ドキュメントコメントで確認済み)。不明時は -1.0 が入るため null 扱いにする。
    // 万一将来のバージョンでスケールが変わった場合に備え、1.0 を超える値が
    // 来た場合は「すでに 0-100 で入っている」とみなして素通しする防御的な
    // 実装にしている。
    final rawLevel = location.battery.level;
    final int? batteryLevelPercent;
    if (rawLevel < 0) {
      batteryLevelPercent = null;
    } else if (rawLevel <= 1.0) {
      batteryLevelPercent = (rawLevel * 100).round();
    } else {
      batteryLevelPercent = rawLevel.round();
    }

    _seq += 1;
    final sample = LocationSample(
      seq: _seq,
      providerId: id,
      recordedAt: recordedAt,
      receivedAt: receivedAt,
      latitude: location.coords.latitude,
      longitude: location.coords.longitude,
      accuracy: _sanitize(location.coords.accuracy),
      altitude: location.coords.altitude,
      speed: _sanitize(location.coords.speed),
      speedAccuracy: _sanitize(location.coords.speedAccuracy),
      heading: _sanitize(location.coords.heading),
      isMoving: location.isMoving,
      activity: _activityTypeToString(location.activity.type),
      activityConfidence: _activityConfidenceToInt(location.activity.confidence),
      odometer: location.odometer,
      batteryLevelPercent: batteryLevelPercent,
      batteryCharging: location.battery.isCharging,
      isMock: location.isMock,
    );

    _samplesController.add(sample);
  }

  /// tracelet の `ActivityType` (camelCase enum) を fbg と同じ表記の
  /// snake_case 文字列に変換する。プロバイダ間でログの表記を揃えることで、
  /// 後段の集計・比較を「同じ語彙」で行えるようにするための正規化。
  static String _activityTypeToString(tl.ActivityType type) {
    switch (type) {
      case tl.ActivityType.still:
        return 'still';
      case tl.ActivityType.walking:
        return 'walking';
      case tl.ActivityType.running:
        return 'running';
      case tl.ActivityType.onFoot:
        return 'on_foot';
      case tl.ActivityType.inVehicle:
        return 'in_vehicle';
      case tl.ActivityType.onBicycle:
        return 'on_bicycle';
      case tl.ActivityType.unknown:
        return 'unknown';
    }
  }

  /// tracelet は活動認識の確信度を 0-100 の連続値ではなく
  /// low/medium/high の 3 段階 enum でしか公開していない。
  /// fbg 側の [LocationSample.activityConfidence] (0-100) と型を揃えるため、
  /// 各段階の代表値 (バケットの中央付近の値) に変換する近似値であり、
  /// 元の連続値を復元できるものではないことに注意。
  static int _activityConfidenceToInt(tl.ActivityConfidence confidence) {
    switch (confidence) {
      case tl.ActivityConfidence.low:
        return 25;
      case tl.ActivityConfidence.medium:
        return 60;
      case tl.ActivityConfidence.high:
        return 90;
    }
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

    // tracelet 自身の権限 API にもリクエストさせ、SDK 側が実際にどう認識
    // したかを記録する。tracelet の requestLocationAuthorization は
    // notDetermined -> whenInUse -> always の順にエスカレーションする設計
    // なので、whenInUse で止まっていたら追加でもう一度呼び出す。
    var tlStatus = await tl.Tracelet.requestLocationAuthorization();
    if (tlStatus == tl.AuthorizationStatus.whenInUse) {
      tlStatus = await tl.Tracelet.requestLocationAuthorization();
    }

    final outcome = PermissionOutcome(
      fineLocationGranted: whenInUseStatus.isGranted,
      backgroundLocationGranted: alwaysStatus.isGranted,
      activityRecognitionGranted: activityStatus.isGranted,
      notificationsGranted: notificationStatus.isGranted,
      rawStatus:
          'tracelet=${tlStatus.name},whenInUse=$whenInUseStatus,'
          'always=$alwaysStatus,activity=$activityStatus,'
          'notification=$notificationStatus',
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
    await tl.Tracelet.start();
    _isTracking = true;
  }

  /// 計測を停止する。
  ///
  /// __重要__: tracelet も Android では `AndroidConfig.foregroundService`
  /// による常駐通知付きフォアグラウンドサービスとして動作する。
  /// __Dart 側のフラグで早期 return してはならない。__
  ///
  /// `stop()` を呼び忘れるとサービスと常駐通知が動き続け、もう一方の
  /// プロバイダ (fbg) を起動した際にバッテリー消費が二重にかかり
  /// 比較実験が成立しなくなる。
  ///
  /// 本プロバイダは `stopOnTerminate: false` で動作するため、アプリが
  /// OS に終了させられてもネイティブのフォアグラウンドサービスは
  /// 動き続ける。アプリ再起動直後の [_isTracking] は false だが、
  /// 実際にはサービスが生きている、という状態が起こりうる。
  ///
  /// そこで早期 return すると、その生き残ったサービスを止められないまま
  /// もう一方のプロバイダを起動してしまう。フォアグラウンドサービスが
  /// 2 つ走れば電池消費はおよそ倍になり、$399 の判断が乗っている
  /// 電池比較そのものが壊れる。
  ///
  /// したがって状態にかかわらず必ず SDK の `stop()` を呼ぶ。
  @override
  Future<void> stop() async {
    try {
      await tl.Tracelet.stop();
    } finally {
      _isTracking = false;
    }
  }

  /// tracelet が自前の SQLite に永続化した記録を読み出す。
  ///
  /// tracelet の `SQLQuery` は fbg と違い時刻範囲での絞り込みに対応する
  /// (`start` / `end`)。そのため件数の算出はプラグイン側に任せられる。
  ///
  /// 破壊的な削除系 API は決して呼ばない。件数を数えやすくするために
  /// DB を消す実装にすると、取り違えた場合に実測データそのものを失う。
  @override
  Future<PluginRecordStats> readPluginRecords({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final totalCount = await tl.Tracelet.getCount();
      final records = await tl.Tracelet.getLocations(
        tl.SQLQuery(start: from, end: to),
      );

      final timestamps = <DateTime>[];
      for (final record in records) {
        final parsed = DateTime.tryParse(record.timestamp)?.toUtc();
        if (parsed == null) continue;
        timestamps.add(parsed);
      }
      timestamps.sort();

      return PluginRecordStats(
        supported: true,
        totalCount: totalCount,
        countInWindow: records.length,
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
    await _locationSub?.cancel();
    await _motionChangeSub?.cancel();
    await _activityChangeSub?.cancel();
    await _providerChangeSub?.cancel();
    _locationSub = null;
    _motionChangeSub = null;
    _activityChangeSub = null;
    _providerChangeSub = null;
    await _samplesController.close();
    await _eventsController.close();
  }
}
