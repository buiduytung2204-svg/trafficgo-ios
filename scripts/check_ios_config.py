"""Static checks runnable on Windows; do not replace Xcode compilation/signing."""
from pathlib import Path
import plistlib
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
info=plistlib.loads((root/'mobile/ios/Runner/Info.plist').read_bytes())
assert info['CFBundleDisplayName']=='TrafficGo'
assert info['NSLocationWhenInUseUsageDescription']
assert 'NSLocationAlwaysAndWhenInUseUsageDescription' not in info
assert 'location' not in info.get('UIBackgroundModes',[])
project=(root/'mobile/ios/Runner.xcodeproj/project.pbxproj').read_text()
assert 'vn.trafficgo.trafficgo' in project
assert 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;' in project
assert 'FlutterGeneratedPluginSwiftPackage' not in project
for path in ['mobile/ios/Runner.xcworkspace/contents.xcworkspacedata',
             'mobile/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
             'mobile/android/app/src/main/AndroidManifest.xml']:
    ET.parse(root/path)
print('iOS static configuration checks passed (not an iOS build).')
