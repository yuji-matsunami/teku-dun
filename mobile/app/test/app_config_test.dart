import 'package:flutter_test/flutter_test.dart';

import 'package:teku_dun/src/config/app_config.dart';

void main() {
  test('APIのURL指定を必須とする', () {
    expect(
      AppConfig.fromEnvironment,
      throwsA(isA<AppConfigurationException>()),
    );
  });

  test('HTTPSのAPI URLを受け入れて末尾のスラッシュを除去する', () {
    expect(
      AppConfig.fromBaseUrl(' https://api.example.test/ ').apiBaseUrl,
      'https://api.example.test',
    );
  });

  test('認証情報やリクエストデータを含む可能性があるURLを拒否する', () {
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
