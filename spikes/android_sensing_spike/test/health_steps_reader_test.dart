import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

import 'package:android_sensing_spike/core/models/tracking_event.dart';
import 'package:android_sensing_spike/health/health_steps_reader.dart';

// 実機 / Health Connect が無い CI 環境でも検証できるよう、ここでは
// プラットフォームチャネル (MethodChannel) を経由しない「値オブジェクトの
// 変換ロジック」だけをテストする。checkAvailability / requestPermission /
// readSteps 自体は実際の Health Connect 呼び出しを伴うため、実機での
// 動作確認が必要 (このテストではカバーしない)。
void main() {
  group('HealthAvailability.toJson', () {
    test('status が null の場合はキー自体を出力しない', () {
      const availability = HealthAvailability(
        status: null,
        canRead: false,
        message: 'Health Connect がインストールされていません。',
      );

      final json = availability.toJson();
      expect(json.containsKey('status'), isFalse);
      expect(json['canRead'], isFalse);
      expect(json['message'], isNotEmpty);
    });

    test('status がある場合は enum 名で出力する', () {
      const availability = HealthAvailability(
        status: HealthConnectSdkStatus.sdkAvailable,
        canRead: true,
        message: 'Health Connect は利用可能です。',
      );

      expect(availability.toJson()['status'], 'sdkAvailable');
    });
  });

  group('HealthPermissionResult.toJson', () {
    test('unavailable の場合は status だけを出力し、他は省略できる', () {
      const result = HealthPermissionResult(status: HealthPermissionStatus.unavailable);

      final json = result.toJson();
      expect(json['status'], 'unavailable');
      expect(json.containsKey('requestReturnedTrue'), isFalse);
      expect(json.containsKey('hasPermissionsAfterRequest'), isFalse);
      expect(json.containsKey('error'), isFalse);
    });

    test('denied の場合に granted / denied / unavailable を区別できる', () {
      const granted = HealthPermissionResult(
        status: HealthPermissionStatus.granted,
        requestReturnedTrue: true,
        hasPermissionsAfterRequest: true,
      );
      const denied = HealthPermissionResult(
        status: HealthPermissionStatus.denied,
        requestReturnedTrue: false,
        hasPermissionsAfterRequest: false,
      );

      expect(granted.toJson()['status'], 'granted');
      expect(denied.toJson()['status'], 'denied');
      expect(granted.status, isNot(equals(denied.status)));
    });
  });

  group('StepsSnapshot.toJson', () {
    test('エラー時は totalSteps を省略し error を含める', () {
      final snapshot = StepsSnapshot(
        start: DateTime.utc(2026, 8, 22, 9),
        end: DateTime.utc(2026, 8, 22, 9, 15),
        totalSteps: null,
        dataPointCount: 0,
        sourceApps: const <String>[],
        error: 'timeout',
      );

      final json = snapshot.toJson();
      expect(json.containsKey('totalSteps'), isFalse);
      expect(json['error'], 'timeout');
      expect(json['dataPointCount'], 0);
      expect(json['sourceApps'], isEmpty);
    });

    test('正常時は totalSteps / sourceApps を含み error を含めない', () {
      final snapshot = StepsSnapshot(
        start: DateTime.utc(2026, 8, 22, 9),
        end: DateTime.utc(2026, 8, 22, 9, 15),
        totalSteps: 1234,
        dataPointCount: 3,
        sourceApps: const <String>['com.google.android.apps.fitness'],
      );

      final json = snapshot.toJson();
      expect(json['totalSteps'], 1234);
      expect(json['dataPointCount'], 3);
      expect(json['sourceApps'], ['com.google.android.apps.fitness']);
      expect(json.containsKey('error'), isFalse);
      expect(json['start'], snapshot.start.toIso8601String());
      expect(json['end'], snapshot.end.toIso8601String());
    });
  });

  group('HealthStepsReader.toEvent', () {
    test('healthSnapshot 種別の TrackingEvent を、区間終了時刻を at として生成する', () {
      final reader = HealthStepsReader();
      final snapshot = StepsSnapshot(
        start: DateTime.utc(2026, 8, 22, 9),
        end: DateTime.utc(2026, 8, 22, 9, 15),
        totalSteps: 500,
        dataPointCount: 2,
        sourceApps: const <String>['com.example.health'],
      );

      final event = reader.toEvent(snapshot);

      expect(event.kind, TrackingEventKind.healthSnapshot);
      expect(event.at, snapshot.end);
      expect(event.data['totalSteps'], 500);
      expect(event.data['sourceApps'], ['com.example.health']);

      // JSONL に書き込む際の 1 行分の Map にも問題なく変換できること。
      final line = event.toJson();
      expect(line['type'], 'event');
      expect(line['kind'], TrackingEventKind.healthSnapshot);
    });
  });
}
