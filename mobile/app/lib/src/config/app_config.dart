const defaultApiBaseUrl = 'http://10.0.2.2:8080';

/// A configuration error that is safe to show to an end user.
class AppConfigurationException implements Exception {
  const AppConfigurationException();

  @override
  String toString() => 'The API base URL is invalid.';
}

class AppConfig {
  const AppConfig._({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment({String? value}) {
    final baseUrl =
        value ??
        const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: defaultApiBaseUrl,
        );
    return AppConfig.fromBaseUrl(baseUrl);
  }

  factory AppConfig.fromBaseUrl(String value) {
    final rawValue = value.trim();
    if (rawValue.isEmpty) {
      throw const AppConfigurationException();
    }

    final uri = Uri.tryParse(rawValue);
    if (uri == null || !_isSupported(uri)) {
      throw const AppConfigurationException();
    }

    return AppConfig._(apiBaseUrl: _withoutTrailingSlash(uri.toString()));
  }

  final String apiBaseUrl;

  static bool _isSupported(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }

    try {
      // Accessing port also validates malformed explicit ports.
      uri.port;
    } on FormatException {
      return false;
    }
    return true;
  }

  static String _withoutTrailingSlash(String value) {
    if (value == 'http://' || value == 'https://') {
      return value;
    }
    return value.replaceFirst(RegExp(r'/+$'), '');
  }
}
