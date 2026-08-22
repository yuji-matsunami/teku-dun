import 'package:flutter/foundation.dart' show immutable;

/// 位置情報プラグイン (flutter_background_geolocation / tracelet) から得られる
/// 生データを正規化した、プロバイダ非依存の位置サンプル。
///
/// 両プロバイダはそれぞれ異なる SDK / データ構造を持つが、アプリの他の層
/// (ログ層・メトリクス層・UI) はこのクラスだけを見れば済むようにする。
/// JSONL のログファイルへ 1 レコード 1 行で書き出すことを前提としており、
/// [toJson] は `null` のフィールドを出力から省いてログサイズを抑える。
@immutable
class LocationSample {
  const LocationSample({
    required this.seq,
    required this.providerId,
    required this.recordedAt,
    required this.receivedAt,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.speedAccuracy,
    this.heading,
    this.isMoving,
    this.activity,
    this.activityConfidence,
    this.odometer,
    this.batteryLevelPercent,
    this.batteryCharging,
    this.isMock,
  });

  /// セッション内で単調増加する連番。取りこぼしの検出に使う。
  final int seq;

  /// このサンプルを発行したプロバイダの ID ("fbg" / "tracelet")。
  final String providerId;

  /// OS / プラグインが報告した計測時刻 (UTC)。
  final DateTime recordedAt;

  /// Dart 側 (アプリ) がこのサンプルを受け取った時刻 (UTC)。
  /// [recordedAt] との差分から配信遅延を見積もれる。
  final DateTime receivedAt;

  /// 緯度 (度)。
  final double latitude;

  /// 経度 (度)。
  final double longitude;

  /// 水平精度 (メートル)。値が大きいほど信頼度が低い。
  final double? accuracy;

  /// 高度 (メートル)。
  final double? altitude;

  /// 速度 (m/s)。
  final double? speed;

  /// 速度の精度 (m/s)。
  final double? speedAccuracy;

  /// 進行方位 (度、0-360)。
  final double? heading;

  /// プラグインが判定した「移動中かどうか」のフラグ。
  final bool? isMoving;

  /// 活動認識の結果 (例: "still" / "on_foot" / "in_vehicle")。
  final String? activity;

  /// [activity] の確信度 (0-100)。
  final int? activityConfidence;

  /// プラグインが内部で積算している走行距離 (メートル)。
  final double? odometer;

  /// サンプル取得時点のバッテリー残量 (0-100)。
  final int? batteryLevelPercent;

  /// サンプル取得時点で充電中かどうか。
  final bool? batteryCharging;

  /// モック位置情報 (開発者向け位置情報アプリなど) からの値である疑いがあるか。
  final bool? isMock;

  /// JSONL の 1 行分の Map に変換する。`null` のフィールドは出力しない。
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'type': 'location',
      'seq': seq,
      'providerId': providerId,
      'recordedAt': recordedAt.toIso8601String(),
      'receivedAt': receivedAt.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    };
    void addIfNotNull(String key, Object? value) {
      if (value != null) {
        map[key] = value;
      }
    }

    addIfNotNull('accuracy', accuracy);
    addIfNotNull('altitude', altitude);
    addIfNotNull('speed', speed);
    addIfNotNull('speedAccuracy', speedAccuracy);
    addIfNotNull('heading', heading);
    addIfNotNull('isMoving', isMoving);
    addIfNotNull('activity', activity);
    addIfNotNull('activityConfidence', activityConfidence);
    addIfNotNull('odometer', odometer);
    addIfNotNull('batteryLevelPercent', batteryLevelPercent);
    addIfNotNull('batteryCharging', batteryCharging);
    addIfNotNull('isMock', isMock);
    return map;
  }

  /// [toJson] で得られた Map から復元する。
  factory LocationSample.fromJson(Map<String, dynamic> json) {
    return LocationSample(
      seq: json['seq'] as int,
      providerId: json['providerId'] as String,
      recordedAt: DateTime.parse(json['recordedAt'] as String).toUtc(),
      receivedAt: DateTime.parse(json['receivedAt'] as String).toUtc(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      speedAccuracy: (json['speedAccuracy'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      isMoving: json['isMoving'] as bool?,
      activity: json['activity'] as String?,
      activityConfidence: json['activityConfidence'] as int?,
      odometer: (json['odometer'] as num?)?.toDouble(),
      batteryLevelPercent: json['batteryLevelPercent'] as int?,
      batteryCharging: json['batteryCharging'] as bool?,
      isMock: json['isMock'] as bool?,
    );
  }
}
