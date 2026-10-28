import 'package:shared_preferences/shared_preferences.dart';

class BackendConfig {
  static const key = 'backend-url-override';
  static const buildUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
  static String current = buildUrl;

  static String normalize(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException(
        'Nhập URL gốc, không có token, /health hoặc đường dẫn.',
      );
    }
    final parts = uri.host.split('.').map(int.tryParse).toList();
    final ipv4 =
        parts.length == 4 &&
        parts.every((p) => p != null && p >= 0 && p <= 255);
    final local =
        uri.host == 'localhost' ||
        (ipv4 &&
            (parts[0] == 10 ||
                parts[0] == 127 ||
                (parts[0] == 192 && parts[1] == 168) ||
                (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31)));
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
      throw const FormatException(
        'Dùng HTTPS; HTTP chỉ dành cho máy local hoặc mạng LAN.',
      );
    }
    return uri.replace(path: '').toString();
  }

  static void restore(SharedPreferences prefs) {
    current = buildUrl;
    final saved = prefs.getString(key);
    if (saved != null) {
      try {
        current = normalize(saved);
      } on FormatException {
        /* Keep build default. */
      }
    }
  }

  // Apply on next launch: never switch hosts under an in-flight authenticated request.
  static Future<void> save(SharedPreferences prefs, String value) async {
    if (!await prefs.setString(key, normalize(value))) {
      throw StateError('Không lưu được URL backend.');
    }
  }
}
