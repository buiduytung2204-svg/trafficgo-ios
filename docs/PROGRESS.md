# TrafficGo — trạng thái ngày 23/10/2026

## Audit trên nhánh audit/traffic-performance

Baseline HTTP được đo trên bd36263 trước sửa; báo cáo và artifacts ở docs/PERFORMANCE_AUDIT.md và docs/benchmarks/. Đã thêm coalescing in-flight (không cache), metrics bounded và Server-Timing, giảm refresh traffic idle/hidden/blocked, nguồn raster OSM cấu hình có attribution và không gửi app token, Valhalla adapter/fallback explicit với nhãn ETA không traffic. Traffic trên nền ngoài cần flag xác nhận license; không bật xe máy. Không đổi .env/key/budget, không đăng ký dịch vụ, không push/merge/deploy. codemagic.yaml và main commit bd36263 được giữ nguyên. Live TomTom trace lỗi 0%; duplicate burst 4→1 upstream. Valhalla live, browser full-map render và iPhone chưa đo được; không thay bằng dữ liệu giả. Kiểm tra cuối cập nhật sau khi hoàn tất build.

Kiểm tra cuối audit: `flutter analyze --no-pub` sạch; `flutter test --no-pub`: 24 passed; `pytest -q`: 26 passed, 1 deprecation warning TestClient. Build Web riêng `build/web-audit` và `build/web-osm-audit` đều thành công. Codemagic YAML parse được hai workflows, diff so với main rỗng; `scripts/check_ios_config.py` pass. Plugin url_launcher iOS yêu cầu iOS 13, tương thích target 15 theo cấu hình; chưa có Xcode compile/signing. Shell benchmark có artifacts trước/sau, không imagery/GPU và không thay phép đo browser thực. Tạo commit cục bộ riêng trên nhánh audit sau khi quét secrets; không push.

## Repository public

Theo yêu cầu người dùng, source đã được đẩy lên https://github.com/buiduytung2204-svg/trafficgo-ios, nhánh main. Tên trafficgo đã tồn tại nên dùng trafficgo-ios; không sửa repo cũ. Trước khi push đã quét 113 file trong commit, không có API key/access token cấu hình thật. .env, bộ đếm quota, virtualenv, build artifacts và signing credentials bị Git bỏ qua. Các ghi chú “chưa push” bên dưới là lịch sử trước yêu cầu công khai repository; không đồng nghĩa đã deploy backend hoặc phát hành app.

Chưa đạt nghiệm thu MVP live. Không có credentials TomTom, CI/signing, PostgreSQL server hay iPhone trong môi trường hiện tại. Không push, deploy, publish, mua dịch vụ hoặc tạo chứng chỉ giả.

## Cập nhật sau khi nhận key

Sửa camera bản đồ khi lỗi tile/kéo map: giữ viewport trong bộ nhớ phiên (tâm, zoom, rotation), FlutterMap có key ổn định và keepAlive; lỗi tile/làm mới không gọi reset camera. Khi đang navigation, thao tác kéo/zoom ngừng bám GPS; nút định vị cho phép bám lại, GPS không ép zoom=16 mỗi fix. Nếu người dùng kéo map trong khi chờ GPS hoặc route response, kết quả về không tự di chuyển camera. Thông báo tile error chủ động yêu cầu frame để hiện ngay, không đợi gesture tiếp theo. Analyze sạch, 18 Flutter tests qua, gồm test hồi quy giữ camera sau tile failure/refresh và ngừng bám GPS sau thao tác kéo.

Sửa lỗi thiếu tile khi kéo bản đồ: xác nhận trực tiếp backend trả 429 do chạm DAILY_PROVIDER_BUDGET=2000 (không có bằng chứng quota TomTom cạn). Giảm panBuffer về 0, debounce tile updates 250ms; TileClient hiển thị detail HTTP và tạm dừng theo Retry-After, không tiếp tục gửi loạt tile khi đang bị chặn. Backend đếm từng lần gọi provider thực (retry mới thêm 1), thay cách dự trù 2 cho mọi operation; bộ đếm được lưu file Git-ignored .provider-budget.json và giữ qua restart. Bảo toàn 2000 lượt đã ghi nhận từ phiên trước. Người dùng xác nhận Free/no paid overage; nâng giới hạn cục bộ trong .env lên 5000 để tiếp tục thử, không đổi plan hoặc bật thanh toán TomTom. Analyze sạch; 16 Flutter tests và 16 backend tests qua, gồm backoff 429, đếm actual attempts và giữ quota sau restart.

Sửa luồng nút tìm đường: đặt trạng thái loading trước khi xin GPS để chặn bấm lặp; mỗi attempt upstream bị giới hạn tổng 10s, tối đa 2 attempts + 250ms, Dio chờ 30s thay vì 20s. UI phân biệt timeout/cancel/HTTP lỗi với mất kết nối. Analyze sạch, 15 Flutter tests và 14 backend tests qua. Live request đến kết quả tìm Tân Mai trả HTTP 200, 3 tuyến, CORS localhost hợp lệ. Lỗi trong ảnh người dùng chưa tái hiện được nên không khẳng định timeout là nguyên nhân duy nhất. Backend đã restart; cần thử lại nút trên trình duyệt với GPS thật.

Sửa lỗi rate limit trên màn hình desktop: trước đây tile và tìm kiếm dùng chung 180 request/phút/IP; nay có bucket riêng API=180/phút, tile=600/phút, cấu hình bằng API_REQUESTS_PER_MINUTE và TILE_REQUESTS_PER_MINUTE. Giữ nguyên DAILY_PROVIDER_BUDGET=2000 và giới hạn TomTom, không bật overage. Retry-After tính theo cửa sổ thực, lỗi chỉ rõ nhóm bị giới hạn. Test hồi quy 181 tile liên tiếp vẫn tìm kiếm/tính tuyến được, cùng test hạn mức tile riêng. Backend tests sau sửa: 14 passed (1 warning TestClient). Backend đã restart với bản sửa.

Đã cấu hình TomTom key trong backend/.env (Git ignored), tạo app access token cục bộ và giới hạn CORS cho localhost:5173/127.0.0.1:5173. Không ghi key vào source hoặc báo cáo. Live smoke test thành công: map PNG HTTP 200, traffic PNG Hà Nội HTTP 200, Search trả 3 kết quả, copyright caption/full notices HTTP 200, routing ô tô trả 3 tuyến được chuẩn hóa (4024m/1051s, 3527m/1114s, 5030m/1254s tại thời điểm thử). Đây là một lần quan sát, không chứng minh độ trễ dữ liệu hoặc coverage mọi đường. Backend đã restart với cấu hình mới. Unit test fixture được cách ly khỏi key thật để không tiêu thụ quota. Các đoạn lịch sử bên dưới ghi tình trạng trước khi nhận key; CI/signing, PostgreSQL và iPhone vẫn chưa kiểm chứng. Xe máy tiếp tục bị khóa.

| Phase | Đã làm / file chính | Kiểm tra và phần còn lại |
|---|---|---|
| 1 Research | docs/API_SETUP.md, COST_ESTIMATION.md: nguồn TomTom/Google/HERE chính thức, coverage VN, motorcycle beta, hạn chế Google/non-Google map | TomTom Flow có coverage quốc gia; chưa đo dữ liệu Hà Nội, chưa xác minh đầy đủ license/proxy/cache. Đơn giá overage còn cần dashboard; không kích hoạt trả phí. |
| 2 Architecture | schemas.py, providers/routing.py, database.py, migration 001, ARCHITECTURE.md | RoutingProvider có TomTom thật; Google/HERE trả 501 có lý do. Migration sinh SQL PostgreSQL được; chưa chạy vào PostgreSQL thật. |
| 3 Foundation | Flutter project iOS/Android/Web, app/, main.dart, theme system/light/dark, onboarding, GoRouter | Flutter 3.47.7/Dart 3.13.5 đã cài ngoài repo. Android SDK/Visual Studio C++ thiếu; Edge có nhưng browser automation không khả dụng. |
| 4 Maps/GPS | features/map/map_screen.dart, tile_client.dart, iOS/Android permissions | Raster API qua backend, traffic relative0, chú giải đúng provider, timestamp nhận tile, cache disk tắt, foreground GPS lifecycle. Chưa test GPS thật. |
| 5 Search/Routing | core/api.dart/models.dart, search debounce/cancellation, route preview trong sheet | 3 tuyến tối đa nếu provider trả, ETA/distance/delay, chọn tuyến. Motorcycle khóa rõ ràng. Chưa test API thật vì không key. |
| 6 Navigation | map_screen.dart, models.dart | GPS marker/heading, distance polyline, lệch tuyến 3 fix, refresh 90s, proposal/cooldown, không âm thầm đổi tuyến. ETA active là snapshot, ETA mới là proposal; chưa có map-matched ETA/hướng rẽ/voice đầy đủ. |
| 7 Personalization | app/state.dart, settings/screens.dart | Local saved places + tuyến thường dùng lưu hai điểm, history opt-in, theme/traffic, xóa dữ liệu và secure token. Endpoint sync có JWT; chưa có auth service/login/sync UI. |
| 8 Quality/Security | backend/tests, mobile/test, .gitignore, .env.example, requirements.lock.txt | Test mock/SQLite, rate limiter một worker, timeout/retry, quota nội bộ, input/owner validation, no-store, logs không chứa query/key. Production cần gateway/hard provider quota và attestation/token ngắn hạn. |
| 9 iOS Build | codemagic.yaml, ios/Podfile, iOS project, scripts/check_ios_config.py, assets/icons | Bundle vn.trafficgo.trafficgo, iOS 15, tên TrafficGo, icon tự tạo, Flutter pin 3.47.7, unsigned app/archive và signed IPA workflow. Static config pass; chưa chạy macOS CI, chưa có artifact iOS. |
| 10 Delivery | README.md, WINDOWS_SETUP.md, IOS_BUILD.md, IPA_SIGNING.md, TESTING.md | Tài liệu 3 cách signing; nêu đúng giới hạn free account/unsigned artifact. Cần kiểm tra thực tế và hoàn thiện các mục còn lại dưới đây. |

## Lệnh đã thực chạy

- `python --version`: 3.14.2; `git --version`: 2.52.0.windows.1.
- Flutter stable clone vào C:\Users\tungb\trafficgo-tools\flutter; `flutter create --platforms ios,android,web`, `flutter pub get`, `flutter doctor -v`.
- `python -m venv backend/.venv`, pip install requirements, pip freeze ra lock.
- `pytest -q`: 12 passed, 1 warning ở lần kiểm tra backend mới nhất.
- `alembic upgrade head --sql`: sinh DDL PostgreSQL đủ 5 bảng và indexes/FKs; chưa apply vào PostgreSQL server.
- `flutter test`: 14 passed ở lượt cuối, bao gồm chữ lớn 200% trên kích thước iPhone.
- `flutter analyze`: No issues found ở lượt cuối.
- `flutter build web`: đã tạo build/web JavaScript thành công; có cảnh báo Wasm chưa tương thích secure storage.
- `python scripts/check_ios_config.py`: pass, chỉ là static checks.
- Browser inventory rỗng; thử tạo IAB báo Browser is not available. Không có xác nhận UI tương tác trình duyệt.
- Backend đã khởi động bằng uvicorn trên 127.0.0.1:8000; HTTP health trả status=ok, provider_configured=false; OpenAPI truy cập được. Đây không phải kết nối TomTom thật.
- Repo Git main đã khởi tạo, chưa commit/push. git check-ignore xác nhận .env, .venv và build được bỏ qua.
- codemagic.yaml parse thành công với 2 workflows; bootstrap_env.ps1 kiểm tra cú pháp thành công. Không chạy CI hoặc signing.
- Build Web cuối sau mọi thay đổi: `flutter build web --no-pub --dart-define=API_BASE_URL=http://localhost:8000` thành công, 79.7s; artifact `mobile/build/web/`. Chỉ còn cảnh báo dry-run Wasm của secure_storage_web; JavaScript build thành công.

## Tiếp tục từ đây

1. Chủ tài khoản xác nhận license TomTom phù hợp proxy/raster REST, attribution và lưu tọa độ người dùng; tạo free key, quota cứng, điền backend/.env cục bộ. Không gửi secret trong chat.
2. Chạy backend + app theo WINDOWS_SETUP; thực hiện checklist live API/GPS trong TESTING. Không gọi dữ liệu realtime verified trước khi có bằng chứng.
3. Chuẩn bị PostgreSQL và auth issuer nếu muốn sync; apply migration và kiểm tra cascade. Guest không cần sync.
4. Kết nối repo với Codemagic và chạy unsigned trong free allowance khi có quyền; thu logs. Cung cấp certificate/profile qua secret store để signed workflow export IPA, rồi cài iPhone.
5. Trước public: bền vững hóa quota, device authentication, đánh giá license/privacy/App Store, map-matched navigation và UI localization tiếng Anh. Chưa có turn-by-turn/voice/background/offline maps.


## 2026-10-23 ? Native Valhalla integration

- Branch: `audit/traffic-performance`; no push/merge/deploy. Flutter and Codemagic unchanged.
- Implemented `ValhallaRoutingProvider` in `backend/app/providers/routing.py`; compatibility import retained. Native JSON, precision-6 decoding, units, alternates, multi-leg instructions, 10s deadline, HTTP/malformed-response handling.
- Added `VALHALLA_URL` (legacy alias supported). Local ignored environment selects the user-provided public demo; TomTom keys untouched and traffic unchanged. Fallback off; motorcycle locked.
- Real direct + local FastAPI checks succeeded: 3714 m, 718 s, 198 points, 16 instructions, traffic_aware=false. Only two public demo calls; no load test.
- Commands: pytest (45 passed, one existing Starlette deprecation warning), flutter analyze (no issues), flutter test (24 passed), check_ios_config.py (pass), git diff --check (pass).
- Added docs/VALHALLA.md and opt-in scripts/check_valhalla_live.py. Public demo is development-only; production service and motorcycle verification remain outstanding.


## 2026-10-23 ? Android APK test artifact

- Branch `build/android-test`; no commit/push. User-created `.vscode/` left untouched.
- Installed Android CLI/SDK/NDK locally outside repository; configured existing Java 21. Enabled required notification-library desugaring, debug-only HTTP allowlist for local backend, reduced Gradle memory/workers and preferred IPv4 after a DNS/download failure.
- `flutter --verbose build apk --debug --dart-define=API_BASE_URL=http://192.168.1.115:8000`: success, 298 actionable Gradle tasks. Initial attempt interrupted for NDK install; next attempt hit Maven DNS/download delays; final build completed.
- `apksigner verify --verbose --print-certs`: verifies APK Signature Scheme v2, Android Debug signer. `aapt dump badging`: vn.trafficgo.trafficgo 0.1.0+1, minimum SDK24, target36, arm64-v8a/armeabi-v7a/x86_64.
- Artifact: Documents/TrafficGo-android-test.apk, 161.6 MiB; SHA256 9494eb0c8c6cac4e3dc4888147bd127d32fbb1b4841d2f99f80eb0ef52e31630. ZIP CRC, byte-for-byte copy and absence of configured TomTom key/app token checked.
- Backend started with LAN binding; local LAN health HTTP200. Phone needs same Wi-Fi and existing APP_ACCESS_TOKEN entered in app settings. No firewall changes. No attached Android device: install/GPS/runtime not verified. See docs/ANDROID_TEST.md.


## 2026-10-23 ? Android GPS and tile diagnostics fix

- User reports no permission prompt and system-location-disabled error. Old flow checked service before requesting permission. New LocationService requests foreground permission first, distinguishes denied/blocked/disabled, opens app/system settings from an explicit action, prevents duplicate location requests, falls back to native Android LocationManager after fused-provider timeout/platform error, accepts approximate fresh fixes; no background tracking or stale fake GPS.
- Tile metrics now classify HTTP status, transport, timeout, cancellation and local backoff. Timing errors inherit HTTP status. Cancellation no longer inflates network-error counts. Tile provider requests make one attempt (10s deadline) rather than retrying a failed burst; search/routing retry behavior unchanged. Manual refresh rebuilds both tile layers, preserving camera. Network outages are not eliminated.
- Tests: flutter analyze clean; flutter test 33 passed; pytest 47 passed (one existing Starlette warning). APK build succeeded in 164s. No physical device attached: GPS runtime still needs user validation with Android system Location enabled.
- Documents/TrafficGo-android-test-v2.apk: versionCode2, min SDK24, ARM64/ARMv7/x86_64; apksigner v2 verified, same debug signer as previous APK; ZIP CRC and absence of configured secrets checked. SHA256 57936bf6e547bf9ecb1d8e24a98ed1ab837c38ffbf56fd02c595de27b7b2e19c. Backend reloaded on LAN and health HTTP200.
- Remains on build/android-test, no push; user .vscode untouched.


## 2026-10-23 ? Geoapify search with quota guards

- Local key stored only in ignored backend/.env; local SEARCH_PROVIDER=geoapify. Source default remains TomTom. Valhalla routes and TomTom tiles/traffic unchanged; no paid service, deployment or push.
- Added Geoapify adapter, SQLite atomic daily/rate attempt guard (1000/day UTC, 40/min, 2/s), no retry/fallback, Retry-After cooldown, in-flight coalescing and RAM LRU cache (256 entries, 10min positive/30s empty). Counters only persist, no query/key/GPS history.
- Flutter: min3 chars, 650ms debounce, stale request cancellation, 429 cooldown, provider/source credits retained for saved places and visible Geoapify/OSM credit links. Same-name features <45m deduplicated in backend.
- Actual provider tests found NHS Trung Van and CMC campus2. FastAPI live checks: 3 queries -> 2 upstream calls + 1 RAM cache hit (repeat 3.3ms), allHTTP200. Initial manual probes accounted for: counter4/1000. No claim of account-wide billing lock.
- Validation: pytest56 passed (one existing Starlette warning); flutter test35 passed after updating debounce expectations; analyze clean; APK build3 success90.1s; signature v2 same debug certificate; ZIP integrity/copy verified and no configured keys/tokens in artifact.
- Artifact Documents/TrafficGo-android-test-v3.apk (161.6MiB), SHA256 082a09eaaaca421310e2b38b9cdbb7921292c03a3298fbb483f0455c9650bcd5. Backend LAN server reloaded. Install update for attribution; no attached device for runtime check. Docs: GEOAPIFY.md, PLACE_SEARCH_CHECK.md.


## 2026-10-23 ? Geoapify basemap, web-only preview

- User changed delivery to web only, no APK. TomTom deletion remains conditional on user confirming the new map works.
- Added authenticated Geoapify osm-carto tile proxy; no client key. RAM cache max256/32MiB, honors max-age up to1hour and no-store/no-cache/private; in-flight coalescing, max3 concurrent upstream fetches and paced bursts.
- Shared persistent credit guard2000/day UTC covers search1credit/tile0.25credit. Migrated prior search count without reset; guard uses integer quarter credits and retains search-only limits.
- Geoapify web mode disables TomTom Traffic/attribution calls, retains required Geoapify/OSM attribution. TomTom sources remain for rollback.
- Commands/results: pytest60 passed(one existing warning), flutter test37 passed, analyze clean, flutter build web build/web-geo succeeded70.7s (existing secure-storage Wasm dry-run warning; JS output good). No APK build.
- Live Geo PNG HTTP200, repeat RAM-hit; two calls consumed0.25credit and no TomTom categories. Served index/bootstrap/main JS HTTP200 at localhost:5173; geo proxy route present and configured secrets absent from JS. Tile image visually inspected; full interactive browser not automated.
- Backend LAN process11684/session83811; web static server session67784. Documentation GEOAPIFY.md updated. No push/deploy, user .vscode untouched.


## 2026-10-23 ? Geoapify grey-hole timeout recovery

- User screenshot shows missing tiles and provider timeout. Actual metrics:106 Geo map upstream attempts,3errors,0rate-limited; backend110requests/3errors. Most tiles succeeded; individual failures left holes.
- Added exactly one delayed recovery attempt for Geoapify tile HTTP502/504 only. Never retry429/TomTom/cancelled request; retain abort trigger and stop on disposed client. No full-layer reload or camera reset. Each upstream miss still uses shared credit guard. Persistent network errors remain possible.
- Validation: flutter analyze clean,40 Flutter tests passed (recovery success/permanent timeout/429/cancellation), web JS build success76.5s with existing Wasm dry-run warning. Backend unchanged this turn; prior60tests pass unchanged. No APK/push.
- Web served from build/web-geo-recovery at localhost:5173. HTTP200, served JS SHA256 matches new output; configured keys/tokens absent. User must Ctrl+F5. Full interactive browser not automated.

2026-10-24: Added bounded motorcycle live probe and MOTORCYCLE_VALIDATION.md. Six demo requests succeeded; two profiles avoided provider-classified highways on Hanoi-Hoa Lac sample. This does not certify Vietnamese access restrictions; motorcycle remains disabled. Raw results in docs/motorcycle-probe.json. Initial pytest from repository root could not import app; reran from backend directory.

2026-10-24: User authorized experimental motorcycle coursework mode. Enabled Valhalla motor_scooter mapping end-to-end with vehicle-preserving normalization, no TomTom motorcycle fallback, visible experimental notice, and route clearing on switch. Flutter analyze clean, 40 Flutter tests passed. Added dedicated profile/normalization test. Live backend route HTTP200, motorcycle 1428m/291s plus alternate1690m/385s, traffic_aware=false. Web build succeeded to build/web-motorcycle, served at localhost:5173. No APK, push or deployment.

2026-10-24: User reports field testing satisfactory and requested motorcycle as normal feature. Removed experimental label, updated settings text, retained accurate non-live ETA and road-sign reminder. No routing/profile/fallback changes. Flutter analyze clean; 40 Flutter tests passed. Building web-vehicles for localhost preview; no APK or push.
Web-vehicles build succeeded (72.3s), served localhost:5173 and HTTP200 verified.

## 2026-10-24 — Smart Departure Windows delivery (feature/smart-departure)

- Phase 1: audited existing SQLAlchemy users/saved_routes and Flutter local endpoints. Added commute schedules/occurrences/inbox/installations/device tokens/worker state, migration002, owner indexes/FKs/unique constraints. Previous PostgreSQL unavailable; backed up ignored .env and configured an absolute SQLite file. Existing PostgreSQL/local saved places/trips not deleted. `alembic upgrade head` succeeded; additive migration test preserves legacy saved route, including repeat upgrade/reopen.
- Phase 2: clock-injected Asia/Ho_Chi_Minh engine, full-week recurrence and one-off dates, midnight preparation, correct formula, disabled/terminal states, revision guards, ETA rescheduling. Same-route edits preserve last provider ETA and attempt count; route edits invalidate incompatible ETA. Completed in-flight trips never overwritten.
- Phase 3: separate `python -m app.departure.worker`, 30s tick, persistent120s DB lease; no scheduler in FastAPI lifespan. Short SQLite BEGIN IMMEDIATE transactions/FKs/busy timeout; PostgreSQL row locks. No transaction while awaiting routing. New worker verified running locally after update.
- Phase 4: Valhalla only, live opt-in (enabled locally), max24 attempts/day UTC,6/occurrence,60s global spacing, refresh30/20/15min. Attempts reserved before provider call, persisted across restart; 12s timeout/no immediate retry; Retry-After honored globally; failure retains ETA. No fake realtime or TomTom fallback.
- Phase 5: durable unique inbox events for prepare/departure soon/due, ETA increased, leave earlier and late risk; read state and route payload. Android/iOS permission-based local notifications while receiving foreground events. No closed-app push claim.
- Phase 6: Flutter schedule CRUD/toggle, saved trip/place selection, vehicle/days/time/preparation/buffer/manual seed, computed times/ETA timestamp/source/status, next commute countdown, offline cache/read-only state, worker heartbeat, notification history/read/open route, personal schedule data deletion. Per-install hashed backend credential in secure storage. Scheduled origin is not treated as actual GPS.
- Phase 7: isolated temporary simulation DB and fake clock; all7 CLI scenarios ran with no real HTTP, including ETA15/25/40/60min, increase/decrease, five-minutes/due/late/offline/restart. Tagged SIMULATION_ONLY, no simulation HTTP API.
- Phase 8: PushNotificationProvider interface, per-device token registration/ownership/active state, invalid-token handling test and event+device idempotency hook. FCM/APNs not configured; hook not attached to live worker.
- Phase 9: latest `pytest -q`:76passed (existing Starlette/httpx deprecation warning). `flutter analyze --no-pub`:clean. `flutter test --no-pub`:45passed. Final Flutter JS web build succeeded92.2s (existing secure-storage Wasm dry-run warning, not a JS build error). Codemagic untouched.
- Live integration: created temporary schedule through authenticated HTTP; separate worker called Valhalla once; persisted291s motorcycle ETA, traffic_aware=false and departure_due inbox event; overviewHTTP200. Temporary schedule/session deleted. Persisted quota remains1; never reset routing budget for tests.
- Served latest build/web-departure-final at localhost:5173; HTTP200 and exact bundle hash verified; configured provider keys/access token absent. Full interactive browser/device notification testing not performed.
- Docs: SMART_DEPARTURE.md has Windows commands, API, policy, simulation, privacy, constraints, Firebase next steps. README and ARCHITECTURE updated. Env/backup/SQLite ignored; source secret scan passed.
- No APK, hosting, deployment, commit or push. Work remains on feature/smart-departure. User .vscode untouched. Remaining device/FCM work is explicit in docs.

2026-10-24: User requested worker and APK. Existing worker heartbeat14s verified, no duplicate started. LAN health HTTP200. Flutter debug APK v4 built86.5s with Geoapify and192.168.1.115:8000; apksigner verified v2/same debug signer as previous APK. Manifest verified versionCode4, minSDK24, target36, GPS+POST_NOTIFICATIONS permissions, ARM64/ARMv7/x86_64. Copied to Documents/TrafficGo-smart-departure-v4.apk (169474475bytes). No push/deploy. Configured secret scan of decompressed APK passed; phone installation not tested.

## 2026-10-24 — Integrated journeys, selected routes and expenses

- Audited legacy endpoints-only SavedTrip, coordinate schedule editor and active TomTom defaults.
- Added shared place picker (names/GPS/saved/map), route planner with independent origin/destination, swap invalidation, real alternatives, exact selected geometry snapshots; legacy JSON remains readable.
- Added local versioned journey store with independent outbound/inbound, school/work/personal, pause/delete, linked schedule direction fields, explicit completion history and VND expense CRUD/statistics. Writes serialized; damaged document preserved.
- Added two-tab journey detail, local place metadata/editor, next-journey card and entry points from map menu/settings. Opening saved routes does not recalculate; manual/automatic alternatives require confirmation, saved snapshot not implicitly overwritten.
- Kept existing scheduler/per-install auth/migration and inbox; linked schedule directions and open-route resolution. Explicit limitations: local journeys/expenses not multi-device sync; scheduler ETA is fastest returned route, not re-costing fixed geometry; push when app closed still requires FCM/APNs and device test.
- Retired active TomTom API wiring/fallback and default map selection. Geoapify/Valhalla only; old tile endpoints410. TrafficDataProvider returns unavailable honestly.
- Added persisted interactive routing cap96/day, 60s RAM reuse/coalescing, max2 upstream/max8 pending, persistent Retry-After. Worker retains separate24/day cap. Keys/env not changed.
- Latest backend suite:80passed; all7 isolated simulation scenarios succeeded, no real HTTP. Analyze clean. Final Flutter tests/web artifact verification in progress; see next entry.
- Documentation: docs/JOURNEYS.md has full end-to-end steps, storage/migration/quota/source research and limitations. Codemagic unchanged. No push/deploy.

2026-10-24 final verification: flutter analyze --no-pub clean; flutter test --no-pub 51passed; pytest -q 80passed (one pre-existing Starlette/httpx deprecation warning). All7 fake-clock simulation scenarios passed without real provider calls. Flutter JS Web build build/web-journeys succeeded67.7s; existing secure-storage Wasm dry-run warning does not affect JS output. Codemagic diff empty.

Local API/worker/static Web restarted after confirming no running copies. API health200; worker heartbeat2.5s verified. Live local HTTP integration verified schedule create/edit, outbound/inbound link roundtrip, formula06:40/06:55, revisedbuffer06:45, explicit completion, idempotent repeat, terminal409 and overview. Temporary test account's personal data deleted. No live routing/Geoapify requests were made by this integration. Web localhost:5173 serves exact latest main.dart.js hash; configured keys/tokens absent from web assets. Not a full interactive browser/physical-device acceptance test. No commit/push/deploy or APK in this feature delivery.
