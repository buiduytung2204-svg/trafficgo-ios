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
