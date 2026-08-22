import 'package:flutter/foundation.dart' show immutable;
import 'package:health/health.dart';

import '../core/models/tracking_event.dart';

/// Health Connect (Android) の歩数データを読み取るためのラッパー。
///
/// `health` パッケージ (13.3.2) はメソッドによって引数の渡し方が非対称
/// になっている点に注意すること (実際のパッケージソースで確認済み):
///
///  * [Health.getTotalStepsInInterval] は `startTime` / `endTime` を
///    **位置引数** で受け取る。
///  * [Health.getHealthDataFromTypes] は `startTime` / `endTime` を
///    **名前付き引数** で受け取る。
///
/// また、このクラスは自分のログには UTC の [DateTime] を保持するが、
/// プラグインに渡す直前には `.toLocal()` した値を使う方針にしている。
/// **ただし** インストール済みソース (`health_plugin.dart`) を確認した限り、
/// これらのメソッドは受け取った `DateTime` を即座に
/// `millisecondsSinceEpoch` に変換して Android 側へ渡しており、
/// `millisecondsSinceEpoch` は `DateTime` が local/UTC のどちらであっても
/// 同じ値になる (同一時刻の異なる表現に過ぎない) ため、実際には
/// local/UTC のどちらを渡しても Health Connect への問い合わせ結果に差は
/// 出ない。それでも「ローカル時刻を渡す」という規約を守っておくのは、
/// 将来 health パッケージの実装が変わった場合の保険として無害だからである。
class HealthStepsReader {
  HealthStepsReader({Health? health}) : _health = health ?? Health();

  final Health _health;

  /// [Health.configure] は複数回呼んでも副作用は小さいはずだが、
  /// 無駄な端末情報取得を避けるために一度だけ実行して結果を使い回す。
  Future<void>? _configureFuture;

  Future<void> _ensureConfigured() {
    return _configureFuture ??= _health.configure();
  }

  /// Health Connect の利用可否を確認する。
  ///
  /// [getHealthConnectSdkStatus] の結果を UI 表示向けの日本語メッセージに
  /// マッピングする。この呼び出し自体は例外を投げない
  /// (プラグイン側も try/catch 済みで null を返す実装になっている)。
  Future<HealthAvailability> checkAvailability() async {
    try {
      await _ensureConfigured();
      final status = await _health.getHealthConnectSdkStatus();

      if (status == HealthConnectSdkStatus.sdkAvailable) {
        return HealthAvailability(
          status: status,
          canRead: true,
          message: 'Health Connect は利用可能です。',
        );
      }

      if (status == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) {
        return HealthAvailability(
          status: status,
          canRead: false,
          message: 'Health Connect の更新が必要です。Play ストアから更新してください。',
        );
      }

      // sdkUnavailable または null (取得失敗) はまとめて「未インストール/未対応」扱いにする。
      return HealthAvailability(
        status: status,
        canRead: false,
        message: 'Health Connect がインストールされていないか、この端末では利用できません。',
      );
    } catch (e) {
      return HealthAvailability(
        status: null,
        canRead: false,
        message: 'Health Connect の状態確認中にエラーが発生しました: $e',
      );
    }
  }

  /// Health Connect アプリのインストール導線 (Play ストア) を開く。
  /// 導線を開けなくてもアプリの継続動作に支障はないため、
  /// 失敗は握りつぶして呼び出し元には何も返さない。
  Future<void> openHealthConnectInstall() async {
    try {
      await _ensureConfigured();
      await _health.installHealthConnect();
    } catch (_) {
      // installHealthConnect 自体はプラグイン内部で例外を握りつぶす実装だが、
      // configure() 側の失敗も想定して二重に保護しておく。
    }
  }

  /// 歩数 (STEPS) の読み取り権限をリクエストする。
  ///
  /// issue #5 では「許可された場合」だけでなく「拒否された場合」の挙動も
  /// 確認する必要があるため、granted / denied / unavailable を明確に
  /// 区別して返す。
  ///
  /// 判定は [Health.requestAuthorization] の戻り値を主として使い、
  /// [Health.hasPermissions] の結果は「実際に許可庫に反映されているか」の
  /// 参考情報として合わせて保持する (両者が食い違うことがあり得るため)。
  Future<HealthPermissionResult> requestPermission() async {
    try {
      final availability = await checkAvailability();
      if (!availability.canRead) {
        return HealthPermissionResult(
          status: HealthPermissionStatus.unavailable,
          error: availability.message,
        );
      }

      await _ensureConfigured();
      final requestGranted = await _health.requestAuthorization(
        <HealthDataType>[HealthDataType.STEPS],
        permissions: <HealthDataAccess>[HealthDataAccess.READ],
      );
      final hasPermissionsAfterRequest = await _health.hasPermissions(
        <HealthDataType>[HealthDataType.STEPS],
        permissions: <HealthDataAccess>[HealthDataAccess.READ],
      );

      return HealthPermissionResult(
        status: requestGranted ? HealthPermissionStatus.granted : HealthPermissionStatus.denied,
        requestReturnedTrue: requestGranted,
        hasPermissionsAfterRequest: hasPermissionsAfterRequest,
      );
    } catch (e) {
      return HealthPermissionResult(
        status: HealthPermissionStatus.unavailable,
        error: e.toString(),
      );
    }
  }

  /// 指定区間の歩数を読み取る。
  ///
  /// [start] / [end] はどのタイムゾーンの [DateTime] で渡されても構わない
  /// (内部で UTC 化してスナップショットに保存し、プラグインへは
  /// ローカル時刻に変換して渡す)。例外は決して外に投げず、
  /// 失敗時は [StepsSnapshot.error] にメッセージを詰めて返す。
  Future<StepsSnapshot> readSteps({required DateTime start, required DateTime end}) async {
    final utcStart = start.toUtc();
    final utcEnd = end.toUtc();

    try {
      await _ensureConfigured();
      final localStart = start.toLocal();
      final localEnd = end.toLocal();

      // getTotalStepsInInterval: 位置引数。
      final totalSteps = await _health.getTotalStepsInInterval(localStart, localEnd);

      // getHealthDataFromTypes: 名前付き引数。
      final points = await _health.getHealthDataFromTypes(
        types: <HealthDataType>[HealthDataType.STEPS],
        startTime: localStart,
        endTime: localEnd,
      );

      // sourceName がどのアプリ由来のデータかを表す (health_data_point.dart で確認済み)。
      // 歩数の記録元アプリが期待と異なるケースを検出するために重複を除いて集める。
      final sourceApps = points
          .map((HealthDataPoint p) => p.sourceName)
          .where((String name) => name.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();

      return StepsSnapshot(
        start: utcStart,
        end: utcEnd,
        totalSteps: totalSteps,
        dataPointCount: points.length,
        sourceApps: sourceApps,
      );
    } catch (e) {
      return StepsSnapshot(
        start: utcStart,
        end: utcEnd,
        totalSteps: null,
        dataPointCount: 0,
        sourceApps: const <String>[],
        error: e.toString(),
      );
    }
  }

  /// [StepsSnapshot] を、位置情報サンプルと同じ JSONL に書き込める
  /// [TrackingEvent] に変換する。
  /// イベント時刻には「問い合わせ区間の終了時刻」を使う。これにより、
  /// 別途 `DateTime.now()` を読む必要がなくなり、スナップショットの
  /// 内容と時刻が常に整合する。
  TrackingEvent toEvent(StepsSnapshot snapshot) {
    return TrackingEvent(
      at: snapshot.end,
      kind: TrackingEventKind.healthSnapshot,
      data: snapshot.toJson(),
    );
  }
}

/// Health Connect が利用可能かどうかの判定結果。
@immutable
class HealthAvailability {
  const HealthAvailability({
    required this.status,
    required this.canRead,
    required this.message,
  });

  /// `getHealthConnectSdkStatus` の生の結果 (取得できなかった場合は null)。
  final HealthConnectSdkStatus? status;

  /// 歩数の読み取りを試みてよい状態かどうか。
  final bool canRead;

  /// UI にそのまま表示できる日本語メッセージ。
  final String message;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (status != null) 'status': status!.name,
      'canRead': canRead,
      'message': message,
    };
  }
}

/// 歩数読み取り権限リクエストの結果種別。
///
/// issue #5 の「権限拒否時の挙動を確認する」という要件のため、
/// granted (許可) / denied (拒否) / unavailable (Health Connect 自体が
/// 使えない) を明確に区別する。
enum HealthPermissionStatus { granted, denied, unavailable }

/// 歩数読み取り権限リクエストの結果。
@immutable
class HealthPermissionResult {
  const HealthPermissionResult({
    required this.status,
    this.requestReturnedTrue,
    this.hasPermissionsAfterRequest,
    this.error,
  });

  /// granted / denied / unavailable のいずれか。
  final HealthPermissionStatus status;

  /// `requestAuthorization` が返した生の真偽値 (unavailable の場合は null)。
  final bool? requestReturnedTrue;

  /// リクエスト直後に `hasPermissions` で確認した結果 (取得できなければ null)。
  final bool? hasPermissionsAfterRequest;

  /// 例外発生時などのエラーメッセージ。
  final String? error;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'status': status.name};
    if (requestReturnedTrue != null) {
      map['requestReturnedTrue'] = requestReturnedTrue;
    }
    if (hasPermissionsAfterRequest != null) {
      map['hasPermissionsAfterRequest'] = hasPermissionsAfterRequest;
    }
    if (error != null) {
      map['error'] = error;
    }
    return map;
  }
}

/// 指定区間の歩数読み取り結果。
///
/// [start] / [end] は常に UTC で保持する (アプリ内の他のログ・
/// モデルクラスと形式を揃えるため)。
@immutable
class StepsSnapshot {
  const StepsSnapshot({
    required this.start,
    required this.end,
    required this.totalSteps,
    required this.dataPointCount,
    this.sourceApps = const <String>[],
    this.error,
  });

  /// 問い合わせ区間の開始時刻 (UTC)。
  final DateTime start;

  /// 問い合わせ区間の終了時刻 (UTC)。
  final DateTime end;

  /// `getTotalStepsInInterval` が返した合計歩数。取得に失敗した場合は null。
  final int? totalSteps;

  /// `getHealthDataFromTypes` が返したデータポイント数。
  final int dataPointCount;

  /// データポイントの記録元アプリ名 (`HealthDataPoint.sourceName`) の重複なし一覧。
  /// 歩数が期待と異なるアプリから記録されていないかを確認するために使う。
  final List<String> sourceApps;

  /// 読み取り中に発生したエラーメッセージ。失敗しても例外は投げず、ここに格納する。
  final String? error;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'dataPointCount': dataPointCount,
      'sourceApps': sourceApps,
    };
    if (totalSteps != null) {
      map['totalSteps'] = totalSteps;
    }
    if (error != null) {
      map['error'] = error;
    }
    return map;
  }
}
