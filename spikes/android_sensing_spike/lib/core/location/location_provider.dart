import 'package:flutter/foundation.dart' show immutable;

import '../models/location_sample.dart';
import '../models/tracking_event.dart';

/// 権限リクエストの結果を表す不変クラス。
///
/// バックグラウンド計測が動かない原因の多くは権限不足であるため、
/// 各権限が実際に許可されたかをログへ残し、後から原因を切り分けられる
/// ようにする。
@immutable
class PermissionOutcome {
  const PermissionOutcome({
    required this.fineLocationGranted,
    required this.backgroundLocationGranted,
    required this.activityRecognitionGranted,
    required this.notificationsGranted,
    this.rawStatus,
  });

  /// 前景での高精度位置情報 (ACCESS_FINE_LOCATION) が許可されたか。
  /// これが false だと、そもそも位置情報の取得自体ができない。
  final bool fineLocationGranted;

  /// バックグラウンドでの位置情報 (ACCESS_BACKGROUND_LOCATION) が許可されたか。
  /// 「画面ロック中も計測を継続できるか」という本スパイクの中心的な
  /// 確認項目に直結する。
  final bool backgroundLocationGranted;

  /// 活動認識 (ACTIVITY_RECOGNITION) が許可されたか。
  /// isMoving / activity の判定精度に影響するため記録する。
  final bool activityRecognitionGranted;

  /// 通知権限 (POST_NOTIFICATIONS) が許可されたか。
  /// フォアグラウンドサービスの通知が表示できるかに関わる。
  final bool notificationsGranted;

  /// プラットフォーム / プラグインが返す生のステータス文字列 (デバッグ用)。
  final String? rawStatus;

  /// ログ (TrackingEvent.data など) に埋め込むための Map に変換する。
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'fineLocationGranted': fineLocationGranted,
      'backgroundLocationGranted': backgroundLocationGranted,
      'activityRecognitionGranted': activityRecognitionGranted,
      'notificationsGranted': notificationsGranted,
    };
    if (rawStatus != null) {
      map['rawStatus'] = rawStatus;
    }
    return map;
  }
}

/// 2 つの位置情報プロバイダ (flutter_background_geolocation / tracelet) が
/// 実装する共通インターフェース。
///
/// UI 層・ログ層はこの抽象型だけに依存することで、プロバイダの実装差分を
/// 意識せずに済むようにする。実装クラスはこのファイルには含めない
/// (別エージェントが `fbg` 用・`tracelet` 用にそれぞれ実装する)。
///
/// 重要: [samples] / [events] ストリームは、アプリがバックグラウンドや
/// 画面ロック中であっても途切れずにイベントを発行し続けられる実装である
/// ことが前提となる。それこそが本スパイクで検証したい対象そのものである。
abstract class LocationProvider {
  /// プロバイダを一意に識別する ID ("fbg" / "tracelet")。
  /// セッションディレクトリ名や [LocationSample.providerId] に使われる。
  String get id;

  /// UI に表示するための人間可読な名前 (例: "flutter_background_geolocation")。
  String get displayName;

  /// [SessionMeta.providerConfig] に記録される設定値のスナップショット
  /// (計測間隔・精度モードなど)。比較実験の再現性を確保するために使う。
  Map<String, dynamic> get configSummary;

  /// 正規化された位置サンプルのストリーム。
  /// アプリがバックグラウンド/画面ロック中でも発行され続ける必要がある。
  Stream<LocationSample> get samples;

  /// 位置情報以外の出来事 (権限結果・モーション変化・エラーなど) のストリーム。
  Stream<TrackingEvent> get events;

  /// プラグインの初期化 (SDK 設定の適用など) を行う。
  /// [start] より前に一度だけ呼び出すこと。
  Future<void> initialize();

  /// 位置情報・活動認識・通知などの必要な権限をリクエストする。
  Future<PermissionOutcome> requestPermissions();

  /// 計測を開始する。
  Future<void> start();

  /// 計測を停止する。
  Future<void> stop();

  /// リソースを解放する。呼び出し後、このインスタンスは再利用しない。
  Future<void> dispose();

  /// 現在計測中かどうか。
  bool get isTracking;
}
