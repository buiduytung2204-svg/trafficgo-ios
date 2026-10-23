# APK development test

Build from the existing Flutter source (an IPA cannot be converted to Android):

```powershell
cd mobile
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.115:8000
```

The generated APK uses a local debug signing key and is for testing only.
It contains no TomTom key. Android SDK/NDK are installed locally under
`C:\Users\tungb\trafficgo-tools\android-sdk`; these are not repository assets.

1. Copy `TrafficGo-android-test.apk` to the Android phone and open it.
   Allow installation from that browser/file manager when Android asks.
2. Connect the phone and development computer to the same Wi-Fi.
3. Run the backend from `backend`:
   `.venv/Scripts/python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000`.
4. Open `http://192.168.1.115:8000/health` in the phone browser. It should return
   an OK health response. If blocked, check network isolation and the Windows
   firewall rule for Python on the private network; no firewall changes were
   made by the build process.
5. In TrafficGo settings, enter the existing `APP_ACCESS_TOKEN` from your local
   `backend/.env`. Do not enter the TomTom API key. The app stores the access
   token in secure storage.
6. Allow foreground location access when requested and test search/routing.

The IP above is the computer's Wi-Fi address at build time. If it changes,
rebuild with the new address and update the debug-only network-security domain.
The debug manifest permits cleartext only for listed local development hosts;
release networking remains unchanged. The APK still requires the backend;
it will not provide traffic/search/routing on an unrelated network.

No cloud deployment, paid service or GitHub push is part of this APK test.


## GPS and diagnostics fix (build number 2)

- Install the `TrafficGo-android-test-v2.apk` update over the first debug APK.
- Enable Android system Location (quick settings or system Location settings),
  then tap the location button. App permission and system Location are separate.
- The app now requests permission before checking the system service and offers
  an Open Settings action for disabled services or permanently blocked permission.
- Fresh fixes use the default provider first, then native Android LocationManager
  after a provider timeout/error. Approximate fixes are accepted for displaying
  position; no stale cached coordinate is silently substituted.
- Diagnostics show HTTP status/timeout/transport/cancellation/backoff outcomes.
  Backend/upstream timing errors now reflect the HTTP status; cancellation is
  recorded separately from transport failures.
- Tile fetches do not automatically retry a failed burst; routing/search retain
  their existing bounded retry behavior. Refresh reloads both map and traffic
  layers while preserving the camera. Internet outages can still cause errors.
