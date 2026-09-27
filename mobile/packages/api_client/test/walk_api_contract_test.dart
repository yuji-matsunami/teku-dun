import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:teku_dun_api_client/teku_dun_api_client.dart';

import 'health_api_contract_test.dart' show RecordingAdapter;

void main() {
  const sessionId = '10000000-0000-4000-8000-000000000001';
  const eventId = '20000000-0000-4000-8000-000000000001';
  final start = DateTime.utc(2026, 1, 1, 10);

  test('session sends device time as RFC3339 and accepts empty 204', () async {
    final adapter = RecordingAdapter(statusCode: 204, body: '');
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/'))
      ..httpClientAdapter = adapter;
    final response = await TekuDunApiClient(dio: dio).getWalkApi().putSession(
      sessionId: sessionId,
      sessionRequest: SessionRequest((b) => b..startDatetime = start),
    );
    expect(response.statusCode, 204);
    expect(adapter.lastRequest?.method, 'PUT');
    expect(adapter.lastRequest?.path, '/sessions/$sessionId');
    expect(adapter.lastRequest?.data, {'start_datetime': start.toIso8601String()});
  });

  test('location preserves zero coordinates and metre accuracy', () async {
    final adapter = RecordingAdapter(statusCode: 204, body: '');
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/'))
      ..httpClientAdapter = adapter;
    await TekuDunApiClient(dio: dio).getWalkApi().putLocation(
      sessionId: sessionId,
      eventId: eventId,
      locationRequest: LocationRequest((b) => b
        ..recordedAt = start
        ..latitude = 0
        ..longitude = 0
        ..accuracyM = 3),
    );
    expect(adapter.lastRequest?.path, '/sessions/$sessionId/locations/$eventId');
    expect(adapter.lastRequest?.data, {
      'recorded_at': start.toIso8601String(),
      'latitude': 0.0, 'longitude': 0.0, 'accuracy_m': 3.0,
    });
  });

  test('step correction sends fixed interval and revision, surfaces conflict', () async {
    final adapter = RecordingAdapter(statusCode: 409, body: '{"code":"conflict","message":"Conflict"}');
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/'))
      ..httpClientAdapter = adapter;
    final end = start.add(const Duration(seconds: 25));
    await expectLater(
      TekuDunApiClient(dio: dio).getWalkApi().putSteps(
        sessionId: sessionId,
        eventId: eventId,
        stepsRequest: StepsRequest((b) => b
          ..startDatetime = start
          ..endDatetime = end
          ..steps = 0
          ..revision = 2),
      ),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 409)),
    );
    expect(adapter.lastRequest?.path, '/sessions/$sessionId/steps/$eventId');
    expect(adapter.lastRequest?.data, {
      'start_datetime': start.toIso8601String(),
      'end_datetime': end.toIso8601String(),
      'steps': 0, 'revision': 2,
    });
  });
}
