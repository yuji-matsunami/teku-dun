import 'package:flutter_test/flutter_test.dart';

import 'package:teku_dun/src/config/app_config.dart';

void main() {
  test('requires an API URL', () {
    expect(
      AppConfig.fromEnvironment,
      throwsA(isA<AppConfigurationException>()),
    );
  });

  test('accepts an explicit HTTPS API URL and normalizes a trailing slash', () {
    expect(
      AppConfig.fromEnvironment(value: ' https://api.example.test/ ')
          .apiBaseUrl,
      'https://api.example.test',
    );
  });

  test('rejects URLs that could carry credentials or request data', () {
    expect(
      () => AppConfig.fromBaseUrl('https://user:password@example.test'),
      throwsA(isA<AppConfigurationException>()),
    );
    expect(
      () => AppConfig.fromBaseUrl('https://api.example.test?token=secret'),
      throwsA(isA<AppConfigurationException>()),
    );
    expect(
      () => AppConfig.fromBaseUrl('not a URL'),
      throwsA(isA<AppConfigurationException>()),
    );
    expect(
      () => AppConfig.fromBaseUrl('https://api.example.test/v1'),
      throwsA(isA<AppConfigurationException>()),
    );
  });
}
