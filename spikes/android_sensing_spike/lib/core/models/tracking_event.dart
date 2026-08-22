import 'package:flutter/foundation.dart' show immutable;

/// 位置サンプル以外の「出来事」を記録するためのイベント。
///
/// 位置情報のログと同じ JSONL ストリームに書き込むことで、時系列上で
/// 「いつ権限が変わったか」「いつプロバイダを切り替えたか」などを
/// 位置サンプルと突き合わせて確認できるようにする。
@immutable
class TrackingEvent {
  const TrackingEvent({
    required this.at,
    required this.kind,
    this.data = const <String, dynamic>{},
  });

  /// イベント発生時刻 (UTC)。
  final DateTime at;

  /// イベント種別。[TrackingEventKind] の定数を使うこと。
  final String kind;

  /// イベント固有の付加情報。JSON に展開されるため、
  /// "type" / "at" / "kind" というキーは使わないこと。
  final Map<String, dynamic> data;

  /// JSONL の 1 行分の Map に変換する。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': 'event',
      'at': at.toIso8601String(),
      'kind': kind,
      ...data,
    };
  }

  /// [toJson] で得られた Map から復元する。
  /// "type" / "at" / "kind" 以外のキーはすべて [data] に格納される。
  factory TrackingEvent.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json)
      ..remove('type')
      ..remove('at')
      ..remove('kind');
    return TrackingEvent(
      at: DateTime.parse(json['at'] as String).toUtc(),
      kind: json['kind'] as String,
      data: data,
    );
  }
}

/// [TrackingEvent.kind] に使う定数一覧。
/// タイプミスによるログの不整合を防ぐために文字列リテラルを直接使わない。
class TrackingEventKind {
  const TrackingEventKind._();

  /// 計測セッションの開始。
  static const String sessionStart = 'sessionStart';

  /// 計測セッションの終了。
  static const String sessionEnd = 'sessionEnd';

  /// 権限リクエストの結果。
  static const String permissionResult = 'permissionResult';

  /// 静止 <-> 移動の状態変化。
  static const String motionChange = 'motionChange';

  /// 活動認識 (歩行・車両など) の変化。
  static const String activityChange = 'activityChange';

  /// 使用中プロバイダの切り替え。
  static const String providerChange = 'providerChange';

  /// Health Connect などから得た歩数・健康データのスナップショット。
  static const String healthSnapshot = 'healthSnapshot';

  /// バッテリー残量のスナップショット。
  static const String batterySnapshot = 'batterySnapshot';

  /// プロバイダ側で発生したエラー。
  static const String providerError = 'providerError';

  /// アプリのライフサイクル変化 (フォアグラウンド/バックグラウンド/画面ロック等)。
  static const String appLifecycle = 'appLifecycle';
}
