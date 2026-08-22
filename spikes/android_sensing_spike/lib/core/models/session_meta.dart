import 'package:flutter/foundation.dart' show immutable;

/// 1 回の計測セッションのメタ情報。
///
/// `<root>/sessions/<id>/meta.json` として保存され、どのプロバイダを
/// どんな設定で・いつからいつまで動かしたかを後から比較できるようにする。
@immutable
class SessionMeta {
  const SessionMeta({
    required this.id,
    required this.providerId,
    required this.startedAt,
    this.endedAt,
    this.deviceInfo = const <String, dynamic>{},
    this.providerConfig = const <String, dynamic>{},
    this.batteryAtStart,
    this.batteryAtEnd,
    this.note,
  });

  /// セッションを一意に識別する ID (例: "20260822-090000-fbg")。
  final String id;

  /// このセッションで使用したプロバイダの ID ("fbg" / "tracelet")。
  final String providerId;

  /// セッション開始時刻 (UTC)。
  final DateTime startedAt;

  /// セッション終了時刻 (UTC)。計測中は `null`。
  final DateTime? endedAt;

  /// 端末情報のスナップショット (機種名・OS バージョンなど)。
  final Map<String, dynamic> deviceInfo;

  /// プロバイダ設定のスナップショット (間隔・精度モードなど)。
  /// 比較実験の再現性を確保するために保存する。
  final Map<String, dynamic> providerConfig;

  /// セッション開始時点のバッテリー残量 (0-100)。
  final int? batteryAtStart;

  /// セッション終了時点のバッテリー残量 (0-100)。
  final int? batteryAtEnd;

  /// 検証者が残す自由記述メモ (例: "画面ロックしたまま 1 時間放置")。
  final String? note;

  /// 一部のフィールドだけを差し替えた新しいインスタンスを作る。
  /// 注意: nullable フィールドに明示的に `null` を渡しても、
  /// このメソッドの実装上は既存の値が保持される (`??` による簡易実装)。
  SessionMeta copyWith({
    String? id,
    String? providerId,
    DateTime? startedAt,
    DateTime? endedAt,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? providerConfig,
    int? batteryAtStart,
    int? batteryAtEnd,
    String? note,
  }) {
    return SessionMeta(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      providerConfig: providerConfig ?? this.providerConfig,
      batteryAtStart: batteryAtStart ?? this.batteryAtStart,
      batteryAtEnd: batteryAtEnd ?? this.batteryAtEnd,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'providerId': providerId,
      'startedAt': startedAt.toIso8601String(),
      'deviceInfo': deviceInfo,
      'providerConfig': providerConfig,
    };
    if (endedAt != null) map['endedAt'] = endedAt!.toIso8601String();
    if (batteryAtStart != null) map['batteryAtStart'] = batteryAtStart;
    if (batteryAtEnd != null) map['batteryAtEnd'] = batteryAtEnd;
    if (note != null) map['note'] = note;
    return map;
  }

  factory SessionMeta.fromJson(Map<String, dynamic> json) {
    return SessionMeta(
      id: json['id'] as String,
      providerId: json['providerId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      endedAt: json['endedAt'] != null
          ? DateTime.parse(json['endedAt'] as String).toUtc()
          : null,
      deviceInfo: json['deviceInfo'] != null
          ? Map<String, dynamic>.from(json['deviceInfo'] as Map)
          : const <String, dynamic>{},
      providerConfig: json['providerConfig'] != null
          ? Map<String, dynamic>.from(json['providerConfig'] as Map)
          : const <String, dynamic>{},
      batteryAtStart: json['batteryAtStart'] as int?,
      batteryAtEnd: json['batteryAtEnd'] as int?,
      note: json['note'] as String?,
    );
  }
}
