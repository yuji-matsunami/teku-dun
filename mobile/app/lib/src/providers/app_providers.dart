import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teku_dun_api_client/teku_dun_api_client.dart';

import '../config/app_config.dart';
import '../gateway/health_gateway.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final apiClientProvider = Provider<TekuDunApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return TekuDunApiClient(basePathOverride: config.apiBaseUrl);
});

final healthGatewayProvider = Provider<HealthGateway>((ref) {
  final healthApi = ref.watch(apiClientProvider).getHealthApi();
  return ApiHealthGateway(GeneratedHealthClient(healthApi));
});

final healthCheckProvider = FutureProvider.autoDispose<HealthCheck>(
  (ref) => ref.watch(healthGatewayProvider).check(),
  // The screen exposes an explicit retry action; do not retry network calls
  // invisibly in the background.
  retry: (_, _) => null,
);
