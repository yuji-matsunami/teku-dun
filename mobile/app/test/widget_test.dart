import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teku_dun/src/app.dart';
import 'package:teku_dun/src/gateway/health_gateway.dart';
import 'package:teku_dun/src/providers/app_providers.dart';

class _FakeHealthGateway implements HealthGateway {
  _FakeHealthGateway(this._responses);

  final List<Future<HealthCheck> Function()> _responses;
  var calls = 0;

  @override
  Future<HealthCheck> check() {
    final response = _responses[calls]();
    calls++;
    return response;
  }
}

Widget _testApp(HealthGateway gateway) {
  return ProviderScope(
    overrides: [healthGatewayProvider.overrideWithValue(gateway)],
    child: const TekuDunApp(),
  );
}

void main() {
  testWidgets('shows loading and then success when the health check passes', (
    tester,
  ) async {
    final response = Completer<HealthCheck>();
    final gateway = _FakeHealthGateway([() => response.future]);

    await tester.pumpWidget(_testApp(gateway));
    expect(find.text('Connecting to the API...'), findsOneWidget);

    response.complete(const HealthCheck.healthy());
    await tester.pumpAndSettle();

    expect(find.text('API is healthy'), findsOneWidget);
    expect(find.text('The health check returned OK.'), findsOneWidget);
  });

  testWidgets('shows a safe error and retries through the gateway', (
    tester,
  ) async {
    final gateway = _FakeHealthGateway([
      () => Future<HealthCheck>.delayed(
        Duration.zero,
        () => throw const HealthGatewayException(),
      ),
      () => Future<HealthCheck>.value(const HealthCheck.healthy()),
    ]);

    await tester.pumpWidget(_testApp(gateway));
    await tester.pumpAndSettle();

    expect(find.text('Could not connect to the API.'), findsOneWidget);
    expect(find.text('The health check failed.'), findsNothing);
    expect(find.byKey(const ValueKey('health-retry-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('health-retry-button')));
    await tester.pumpAndSettle();

    expect(gateway.calls, 2);
    expect(find.text('API is healthy'), findsOneWidget);
  });
}
