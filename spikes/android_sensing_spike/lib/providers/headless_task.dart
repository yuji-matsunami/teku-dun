import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:path_provider/path_provider.dart';
import 'package:tracelet/tracelet.dart' as tl;

import '../core/log/session_store.dart';
import '../core/models/location_sample.dart';
import '../core/models/tracking_event.dart';

/// アプリ (Dart isolate) が停止したあとも記録を続けるためのヘッドレスタスク。
///
/// ## なぜ必要か
///
/// 両ライブラリとも `stopOnTerminate: false` で動くため、Android が
/// Flutter の Dart isolate を停止させても、ネイティブ側のフォアグラウンド
/// サービスは記録を続ける。実機のログでもそれが確認できている:
///
/// ```
/// ║ MainActivity was destroyed
/// ╟─ stopOnTerminate: false
/// ╟─ enabled: true
/// ```
///
/// しかしこのアプリの JSONL ログは Dart 側でしか書けない。
/// ヘッドレスタスクを登録しないと、この時点で **記録だけが途切れる**。
/// ログの見た目上は「ライブラリが計測を止めた」場合と区別がつかず、
/// 実際には正常に動いていたライブラリを不採用にしかねない。
///
/// なお `enableHeadless: true` を設定しただけでは動かない。
/// [bg.BackgroundGeolocation.registerHeadlessTask] /
/// [tl.Tracelet.registerHeadlessTask] による登録が別途必要である。
/// 実機ログで `☯️ HeadlessMode? true` と出ていてもコールバックが
/// 登録されていなければ何も実行されない。
///
/// ## 制約
///
/// - ヘッドレス isolate はアプリのメモリを一切共有しない。
///   対象セッションはディスク上の `active_session.json` からしか分からない
///   ([SessionStore.writeActiveSessionId] を参照)。
/// - トップレベル関数であり、かつ `@pragma('vm:entry-point')` が必要。
///   これが無いとリリースビルドのツリーシェイクで削除される。
/// - ここで書いたレコードには `headless: true` を付ける。
///   「アプリが死んでいた区間」を後から判別できるようにするため。

/// `flutter_background_geolocation` 用のヘッドレスタスク。
@pragma('vm:entry-point')
Future<void> fbgHeadlessTask(bg.HeadlessEvent headlessEvent) async {
  // ヘッドレス isolate ではバインディングが未初期化。
  // path_provider などのプラグインを使う前に必ず初期化する。
  WidgetsFlutterBinding.ensureInitialized();

  switch (headlessEvent.name) {
    case bg.Event.LOCATION:
      final location = headlessEvent.event as bg.Location;
      // fbg の使い捨てサンプルは通常時と同様に除外する。
      // ここで数えると、アプリが落ちていた区間だけ件数が水増しされる。
      if (location.sample) return;
      await _appendSample(
        providerId: 'fbg',
        recordedAt: _parseTimestamp(location.timestamp),
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
        accuracy: _sanitize(location.coords.accuracy),
        altitude: _sanitize(location.coords.altitude),
        speed: _sanitize(location.coords.speed),
        heading: _sanitize(location.coords.heading),
        isMoving: location.isMoving,
        activity: location.activity.type,
        activityConfidence: location.activity.confidence,
        odometer: location.odometer,
        batteryLevelPercent: _batteryPercent(location.battery.level),
        batteryCharging: location.battery.isCharging,
        isMock: location.mock,
      );

    case bg.Event.MOTIONCHANGE:
      final location = headlessEvent.event as bg.Location;
      await _appendEvent(TrackingEventKind.motionChange, <String, dynamic>{
        'providerId': 'fbg',
        'isMoving': location.isMoving,
      });

    case bg.Event.TERMINATE:
      await _appendEvent(TrackingEventKind.appLifecycle, <String, dynamic>{
        'providerId': 'fbg',
        'state': 'terminated',
        'note': 'アプリが終了した。以降の記録はヘッドレスタスクによるもの。',
      });

    case bg.Event.BOOT:
      await _appendEvent(TrackingEventKind.appLifecycle, <String, dynamic>{
        'providerId': 'fbg',
        'state': 'boot',
      });
  }
}

/// `tracelet` 用のヘッドレスタスク。
///
/// fbg と違い [tl.HeadlessEvent.event] は型付きオブジェクトではなく
/// 生の `Map` である (`headless_event.dart` で確認済み)。
/// そのためフィールドの取り出し方が非対称になる。
@pragma('vm:entry-point')
Future<void> traceletHeadlessTask(tl.HeadlessEvent headlessEvent) async {
  WidgetsFlutterBinding.ensureInitialized();

  final map = headlessEvent.event;

  switch (headlessEvent.name) {
    case 'location':
      final coords = map['coords'];
      if (coords is! Map) return;
      final c = coords.map<String, Object?>(
        (Object? k, Object? v) => MapEntry(k.toString(), v),
      );
      final battery = map['battery'];
      final b = battery is Map
          ? battery.map<String, Object?>(
              (Object? k, Object? v) => MapEntry(k.toString(), v),
            )
          : const <String, Object?>{};
      final activity = map['activity'];
      final a = activity is Map
          ? activity.map<String, Object?>(
              (Object? k, Object? v) => MapEntry(k.toString(), v),
            )
          : const <String, Object?>{};

      final latitude = _toDouble(c['latitude']);
      final longitude = _toDouble(c['longitude']);
      if (latitude == null || longitude == null) return;

      await _appendSample(
        providerId: 'tracelet',
        recordedAt: _parseTimestamp(map['timestamp']),
        latitude: latitude,
        longitude: longitude,
        accuracy: _sanitize(_toDouble(c['accuracy'])),
        altitude: _sanitize(_toDouble(c['altitude'])),
        speed: _sanitize(_toDouble(c['speed'])),
        heading: _sanitize(_toDouble(c['heading'])),
        isMoving: map['isMoving'] as bool?,
        activity: a['type']?.toString(),
        activityConfidence: _toInt(a['confidence']),
        odometer: _toDouble(map['odometer']),
        batteryLevelPercent: _batteryPercent(_toDouble(b['level'])),
        batteryCharging: b['isCharging'] as bool?,
        isMock: map['isMock'] as bool?,
      );

    case 'motionchange':
      await _appendEvent(TrackingEventKind.motionChange, <String, dynamic>{
        'providerId': 'tracelet',
        'isMoving': map['isMoving'],
      });

    case 'terminate':
      await _appendEvent(TrackingEventKind.appLifecycle, <String, dynamic>{
        'providerId': 'tracelet',
        'state': 'terminated',
        'note': 'アプリが終了した。以降の記録はヘッドレスタスクによるもの。',
      });
  }
}

/// 進行中セッションの events.jsonl へ位置サンプルを1件追記する。
///
/// 計測中でなければ何もしない。ヘッドレスタスクは計測していない時間帯にも
/// 呼ばれうるため、この判定を省くと無関係なイベントがセッションへ混入する。
Future<void> _appendSample({
  required String providerId,
  required DateTime? recordedAt,
  required double latitude,
  required double longitude,
  double? accuracy,
  double? altitude,
  double? speed,
  double? heading,
  bool? isMoving,
  String? activity,
  int? activityConfidence,
  double? odometer,
  int? batteryLevelPercent,
  bool? batteryCharging,
  bool? isMock,
}) async {
  await _withActiveSession((store, sessionId) async {
    final receivedAt = DateTime.now().toUtc();
    final sample = LocationSample(
      // ヘッドレス isolate は主 isolate の連番を知らない。
      // seq は 0 とし、headless フラグで区別する。
      // 集計は recordedAt 順で行うため seq には依存しない。
      seq: 0,
      providerId: providerId,
      recordedAt: recordedAt ?? receivedAt,
      receivedAt: receivedAt,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: altitude,
      speed: speed,
      heading: heading,
      isMoving: isMoving,
      activity: activity,
      activityConfidence: activityConfidence,
      odometer: odometer,
      batteryLevelPercent: batteryLevelPercent,
      batteryCharging: batteryCharging,
      isMock: isMock,
    );

    final sink = store.sinkFor(sessionId);
    try {
      await sink.append(<String, dynamic>{...sample.toJson(), 'headless': true});
    } finally {
      await sink.close();
    }
  });
}

/// 進行中セッションの events.jsonl へイベントを1件追記する。
Future<void> _appendEvent(String kind, Map<String, dynamic> data) async {
  await _withActiveSession((store, sessionId) async {
    final sink = store.sinkFor(sessionId);
    try {
      await sink.append(
        TrackingEvent(
          at: DateTime.now().toUtc(),
          kind: kind,
          data: <String, dynamic>{...data, 'headless': true},
        ).toJson(),
      );
    } finally {
      await sink.close();
    }
  });
}

/// 計測中セッションがある場合のみ [action] を実行する。
///
/// ヘッドレスタスクから例外を投げてはならない。ネイティブ側から呼ばれる
/// ため、投げても誰も受け取れないうえ、以降のイベント配信を壊しかねない。
Future<void> _withActiveSession(
  Future<void> Function(SessionStore store, String sessionId) action,
) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final store = SessionStore(Directory(dir.path));
    final sessionId = await store.readActiveSessionId();
    if (sessionId == null) return;
    await action(store, sessionId);
  } catch (_) {
    // ヘッドレスで失敗しても、計測そのものは継続させる。
  }
}

/// プラグインのタイムスタンプ (ISO-8601 文字列 / epoch ミリ秒) を UTC に変換する。
DateTime? _parseTimestamp(Object? raw) {
  if (raw is String) return DateTime.tryParse(raw)?.toUtc();
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  return null;
}

/// 「不明」を表すセンチネル値 (-1) を null に均す。
///
/// fbg は速度・精度が不明なとき -1.0 を返す。そのまま記録すると
/// 画面に `速度: -1.0 m/s` と出たり、集計へ紛れ込んだりする。
double? _sanitize(double? value) {
  if (value == null) return null;
  if (value < 0) return null;
  return value;
}

/// 電池残量 (0.0〜1.0、不明は -1.0) を 0〜100 の整数に変換する。
int? _batteryPercent(double? level) {
  if (level == null || level < 0) return null;
  return (level * 100).round();
}

double? _toDouble(Object? v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _toInt(Object? v) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}
