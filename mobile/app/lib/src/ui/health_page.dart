import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

class HealthPage extends ConsumerWidget {
  const HealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthState = ref.watch(healthCheckProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Teku Dun')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: healthState.when(
              loading: _loading,
              data: (_) => const _SuccessState(),
              error: (_, _) => _ErrorState(
                onRetry: () => ref.invalidate(healthCheckProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loading() {
    return const Column(
      key: ValueKey('health-loading-state'),
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text('Connecting to the API...'),
      ],
    );
  }
}

class _SuccessState extends StatelessWidget {
  const _SuccessState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: ValueKey('health-success-state'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, color: Colors.green, size: 48),
        SizedBox(height: 16),
        Text('API is healthy', style: TextStyle(fontSize: 22)),
        SizedBox(height: 8),
        Text('The health check returned OK.'),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('health-error-state'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off, color: Colors.red, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Could not connect to the API.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Check that the API is running and try again.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('health-retry-button'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
