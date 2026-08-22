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
  test('maps a successful generated response to a healthy result', () async {
    final gateway = ApiHealthGateway(_FakeHealthClient(_okResponse()));

    final result = await gateway.check();

    expect(result.status, HealthStatus.healthy);
  });

  test('rejects an empty generated response without exposing details', () {
    final gateway = ApiHealthGateway(_FakeHealthClient(null));

    expect(
      gateway.check(),
      throwsA(
        isA<HealthGatewayException>().having(
          (error) => error.toString(),
          'safe message',
          'The health check failed.',
        ),
      ),
    );
  });

  test(
    'converts transport and serialization failures to a safe exception',
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
              'safe message',
              'The health check failed.',
            ),
          ),
        );
      }
    },
  );
}
