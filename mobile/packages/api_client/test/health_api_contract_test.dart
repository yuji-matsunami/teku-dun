import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:teku_dun_api_client/teku_dun_api_client.dart';

class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('health endpoint uses the base URL and deserializes a 200 response', () async {
    final adapter = RecordingAdapter(
      statusCode: 200,
      body: '{"status":"ok"}',
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/'))
      ..httpClientAdapter = adapter;
    final api = TekuDunApiClient(dio: dio).getHealthApi();

    final response = await api.getHealthz();

    expect(adapter.lastRequest?.method, 'GET');
    expect(adapter.lastRequest?.uri, Uri.parse('https://api.example.test/healthz'));
    expect(response.statusCode, 200);
    expect(response.data?.status, HealthResponseStatusEnum.ok);
  });

  test('readiness endpoint surfaces a 503 response as a DioException', () async {
    final adapter = RecordingAdapter(
      statusCode: 503,
      body: '{"code":"service_unavailable","message":"Service is not ready."}',
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/'))
      ..httpClientAdapter = adapter;
    final api = TekuDunApiClient(dio: dio).getHealthApi();

    await expectLater(
      api.getReadyz(),
      throwsA(
        isA<DioException>().having(
          (exception) => exception.response?.statusCode,
          'status code',
          503,
        ),
      ),
    );
    expect(adapter.lastRequest?.method, 'GET');
    expect(adapter.lastRequest?.uri, Uri.parse('https://api.example.test/readyz'));
  });
}
