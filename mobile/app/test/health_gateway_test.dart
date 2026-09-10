import 'package:flutter_test/flutter_test.dart';
import 'package:teku_dun_api_client/teku_dun_api_client.dart';

import 'package:teku_dun/src/gateway/health_gateway.dart';

class _FakeHealthClient implements HealthClient {
  _FakeHealthClient(this._response, {this.error});

  final HealthResponse? _response;
  final Object? error;

  @override
  Future<HealthResponse?> getHealthz() async {
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return _response;
  }
}

HealthResponse _okResponse() {
  return HealthResponse(
    (builder) => builder.status = HealthResponseStatusEnum.ok,
  );
}

void main() {
  test('生成クライアントの正常レスポンスを正常なヘルスチェック結果に変換する', () async {
    final gateway = ApiHealthGateway(_FakeHealthClient(_okResponse()));

    final result = await gateway.check();

    expect(result.status, HealthStatus.healthy);
  });

  test('生成クライアントの空レスポンスを詳細を公開せずに拒否する', () {
    final gateway = ApiHealthGateway(_FakeHealthClient(null));

    expect(
      gateway.check(),
      throwsA(
        isA<HealthGatewayException>().having(
          (error) => error.toString(),
          '安全なメッセージ',
          'The health check failed.',
        ),
      ),
    );
  });

  test(
    '通信とデシリアライズの失敗を安全な例外に変換する',
    () async {
      for (final error in [
        StateError('private transport details'),
        FormatException('private serialization details'),
      ]) {
        final gateway = ApiHealthGateway(_FakeHealthClient(null, error: error));

        await expectLater(
          gateway.check(),
          throwsA(
            isA<HealthGatewayException>().having(
              (error) => error.toString(),
              '安全なメッセージ',
              'The health check failed.',
            ),
          ),
        );
      }
    },
  );
}
