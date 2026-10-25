"""Windows-safe tests: no Xcode, secrets or real project plist mutations."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('ios_build', Path(__file__).with_name('prepare_ios_build.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class IOSConfigTests(unittest.TestCase):
    def test_https_origin(self):
        self.assertEqual(module.validate_backend('https://example.com/'), ('https://example.com', False))
    def test_lan_http_is_explicit_unsigned_only(self):
        self.assertEqual(module.validate_backend('http://192.168.1.50:8000', True), ('http://192.168.1.50:8000', True))
        for allow, signed in [(False, False), (True, True)]:
            with self.assertRaises(ValueError): module.validate_backend('http://192.168.1.50:8000', allow, signed)
    def test_reject_placeholder_loopback_public_http_and_credentials(self):
        for url in ['', 'https://backend.example.invalid', 'http://localhost:8000', 'https://127.0.0.1', 'http://0.0.0.0', 'http://8.8.8.8', 'https://user:pass@example.com', 'https://example.com/api', 'https://example.com?token=secret']:
            with self.subTest(url=url), self.assertRaises(ValueError): module.validate_backend(url, True)
    def test_prepare_modifies_only_fixture_and_never_embeds_provider_key(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); path=root/'mobile/ios/Runner/Info.plist'; path.parent.mkdir(parents=True)
            path.write_bytes(plistlib.dumps({'CFBundleDisplayName':'TrafficGo'}))
            module.prepare(root, {'API_BASE_URL':'http://192.168.1.50:8000','IOS_ALLOW_LOCAL_HTTP':'1','GEOAPIFY_API_KEY':'do-not-embed'})
            self.assertTrue(plistlib.loads(path.read_bytes())['NSAppTransportSecurity']['NSAllowsArbitraryLoads'])
            self.assertNotIn('do-not-embed', (root/'build/ci/defines.json').read_text())
            with self.assertRaises(ValueError): module.prepare(root, {'API_BASE_URL':'https://example.com'}, True)

if __name__ == '__main__': unittest.main()
