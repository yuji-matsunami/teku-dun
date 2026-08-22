import 'package:teku_dun_api_client/teku_dun_api_client.dart';

enum HealthStatus { healthy }

class HealthCheck {
  const HealthCheck.healthy() : status = HealthStatus.healthy;

  final HealthStatus status;
}

/// A stable, user-safe error boundary for health-check failures.
class HealthGatewayException implements Exception {
  const HealthGatewayException();

  @override
  String toString() => 'The health check failed.';
}

abstract interface class HealthGateway {
  Future<HealthCheck> check();
}

abstract interface class HealthClient {
  Future<HealthResponse?> getHealthz();
}

class GeneratedHealthClient implements HealthClient {
  const GeneratedHealthClient(this._api);

  final HealthApi _api;

  @override
  Future<HealthResponse?> getHealthz() async {
    final response = await _api.getHealthz();
    return response.data;
  }
}

class ApiHealthGateway implements HealthGateway {
  const ApiHealthGateway(this._client);

  final HealthClient _client;

  @override
  Future<HealthCheck> check() async {
    try {
      final response = await _client.getHealthz();
      if (response?.status != HealthResponseStatusEnum.ok) {
        throw const HealthGatewayException();
      }
      return const HealthCheck.healthy();
    } on HealthGatewayException {
      rethrow;
    } catch (_) {
      // Keep transport, serialization, and server details out of the UI.
      throw const HealthGatewayException();
    }
  }
}
