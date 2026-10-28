import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/core/backend_config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    BackendConfig.current = BackendConfig.buildUrl;
  });
  test(
    'Accepts HTTPS origin and explicit local HTTP, strips trailing slash',
    () {
      expect(
        BackendConfig.normalize(' https://my-test.trycloudflare.com/ '),
        'https://my-test.trycloudflare.com',
      );
      expect(
        BackendConfig.normalize('http://192.168.1.10:8000'),
        'http://192.168.1.10:8000',
      );
    },
  );
  test(
    'Rejects insecure remote URLs, credentials, paths, query and invalid ports',
    () {
      for (final value in [
        '',
        'http://example.com',
        'ftp://example.com',
        'https://user:password@example.com',
        'https://example.com/health',
        'https://example.com?token=secret',
        'https://example.com#secret',
        'https://example.com:99999',
        'http://192.168.999.1',
      ]) {
        expect(
          () => BackendConfig.normalize(value),
          throwsFormatException,
          reason: value,
        );
      }
    },
  );
  test('Persists across restart without mutating active host or local account data', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active-account-id', 'local-test-user');
    final old = BackendConfig.current;
    await BackendConfig.save(prefs, 'https://new-tunnel.trycloudflare.com');
    expect(BackendConfig.current, old);
    BackendConfig.restore(prefs);
    expect(BackendConfig.current, 'https://new-tunnel.trycloudflare.com');
    expect(prefs.getString('active-account-id'), 'local-test-user');
  });
  test('Invalid stored override safely falls back to build URL', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BackendConfig.key,
      'https://example.com?token=secret',
    );
    BackendConfig.restore(prefs);
    expect(BackendConfig.current, BackendConfig.buildUrl);
  });
}
