import 'package:flutter/foundation.dart' show immutable;

import '../models/location_sample.dart';
import '../models/tracking_event.dart';

/// プラグインが自前のDBへ永続化した位置記録の件数。
///
/// 本スパイクの結論を左右する切り分けのために使う。
///
/// 2つのライブラリはいずれも `stopOnTerminate: false` で動作し、
/// Android が Flutter の Dart isolate を停止させても、ネイティブ側の
/// フォアグラウンドサービスは記録を続ける。一方このアプリの JSONL ログは
/// Dart 側でしか書けないため、isolate が落ちるとログだけが途切れる。
///
/// この状態は、ログの見た目上「ライブラリが計測を止めた」場合と
/// 区別がつかない。両者を取り違えると、実際には正常に動いていた
/// ライブラリを不採用にしかねない。
///
/// そこでセッション終了時にプラグイン内部の記録件数を読み出し、
/// 自前ログの件数と突き合わせる。
///
/// - 両者がほぼ一致 → Dart 側の取りこぼしは無い
/// - プラグイン側が大幅に多い → **アプリだけが落ち、ライブラリは動いていた**
/// - 両者とも少ない → ライブラリまたは OS が計測を止めた
///
/// なお `flutter_background_geolocation` は、モーション変化時に発生する
/// 使い捨てサンプル (`Location.sample == true`) を自前DBへ保存しない。
/// そのため両者の件数は元々完全には一致しない。差分の解釈には注意する。
@immutable
class PluginRecordStats {
  const PluginRecordStats({
    required this.supported,
    this.totalCount,
    this.countInWindow,
    this.firstAt,
    this.lastAt,
    this.error,
  });

  /// プラグインが記録件数の取得APIを持つか。
  /// 持たない場合は false とし、他のフィールドは null にする。
  final bool supported;

  /// プラグインDBに残っている全記録の件数。
  final int? totalCount;

  /// 問い合わせた期間内に限った記録件数。
  final int? countInWindow;

  /// 期間内で最初に記録された時刻 (UTC)。
  final DateTime? firstAt;

  /// 期間内で最後に記録された時刻 (UTC)。
  /// セッション終了時刻より大幅に古ければ、その時点で計測が止まっている。
  final DateTime? lastAt;

  /// 読み出しに失敗した場合の理由。
  final String? error;

  /// ログ (TrackingEvent.data) へ埋め込むための Map に変換する。
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'supported': supported};
    if (totalCount != null) map['totalCount'] = totalCount;
    if (countInWindow != null) map['countInWindow'] = countInWindow;
    if (firstAt != null) map['firstAt'] = firstAt!.toIso8601String();
    if (lastAt != null) map['lastAt'] = lastAt!.toIso8601String();
    if (error != null) map['error'] = error;
    return map;
  }

  /// [toJson] で得られた Map から復元する。
  factory PluginRecordStats.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? v) =>
        v is String ? DateTime.parse(v).toUtc() : null;
    return PluginRecordStats(
      supported: json['supported'] as bool? ?? false,
      totalCount: json['totalCount'] as int?,
      countInWindow: json['countInWindow'] as int?,
      firstAt: parse(json['firstAt']),
      lastAt: parse(json['lastAt']),
      error: json['error'] as String?,
    );
  }
}

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

  /// プラグインが自前のDBへ永続化した記録の件数を読み出す。
  ///
  /// [from] / [to] は UTC で渡す。プラグインDBはセッションをまたいで
  /// 蓄積されるため、必ず期間で絞り込むこと。
  ///
  /// __破壊的な操作をしてはならない。__ プラグイン側のレコードを削除して
  /// 件数を数え直す実装にすると、取り違えた場合に実測データそのものを
  /// 失う。読み取りのみで完結させること。
  ///
  /// APIを持たないプラグインでは `PluginRecordStats(supported: false)` を
  /// 返す。失敗しても例外を投げず、[PluginRecordStats.error] に理由を入れる。
  ///
  /// 用途は [PluginRecordStats] のドキュメントを参照。
  Future<PluginRecordStats> readPluginRecords({
    required DateTime from,
    required DateTime to,
  });
}
