# Kiểm thử

## Tự động

Từ root trên Windows:

```powershell
cd backend
.venv/Scripts/python -m pytest -q
.venv/Scripts/python -m alembic upgrade head --sql
cd ../mobile
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://localhost:8000
cd ..
python scripts/check_ios_config.py
```

Flutter 3.47.7 / Dart 3.13.5 trong phiên có lỗi LSP với đường dẫn Unicode. Workaround đã tạo junction `C:\Users\tungb\trafficgo-work` trỏ đến `mobile`, chạy analyze/test/build từ junction đó. Đây là cùng source, không phải bản copy. Không cần đổi tên thư mục OneDrive. Thêm SDK `C:\Users\tungb\trafficgo-tools\flutter\bin` vào PATH cho terminal của bạn, hoặc dùng đường dẫn flutter.bat đầy đủ.

Backend tests dùng HTTPX MockTransport và SQLite in-memory để kiểm tra quyền owner; **không chứng minh PostgreSQL hoặc API thật hoạt động**. Bộ test bao gồm lỗi 401/403/429/500, timeout và giới hạn retry, chuẩn hóa/empty/malformed routes, validation, access token, JWT owner access, partial settings, request budget và kích thước body. Có một deprecation warning từ Starlette TestClient dùng httpx; không có test fail.

Flutter tests bao gồm models, ETA, sắp tuyến, cooldown, khoảng cách đến đoạn polyline, lưu hai điểm tuyến, onboarding, settings, saved-empty, bản đồ kích thước iPhone và trạng thái search loading/empty/offline. Provider trong các test được mock rõ ràng. Không chèn dữ liệu test vào runtime. Kiểm tra cuối và số test thực chạy nằm trong PROGRESS.md.

Web build dùng JavaScript; secure_storage_web phiên bản đã chọn chưa hỗ trợ Wasm. Không tuyên bố build Wasm thành công. Trình điều khiển browser của phiên không có browser khả dụng, vì vậy chưa có kiểm thử tương tác trình duyệt hoặc screenshot UI thật. Widget test không thay thế kiểm tra UI iPhone.

## Kiểm thử thực tế sau khi có credentials

1. Khởi động backend với TomTom key/free plan và app token. `/health` phải trả configured=true; `/traffic/status` vẫn không tự khẳng định verified. Health không gọi provider.
2. Mở app với backend HTTPS; xác nhận map Hà Nội có dữ liệu và attribution caption/full notices tải được. Pan/zoom/rotate, toggle traffic; traffic refresh không reload base map. Kiểm tra request counts và quota dashboard.
3. Tìm Hoàn Kiếm và địa điểm khác, thử không có kết quả, offline, sai key, hết quota. Đảm bảo lỗi không chứa key.
4. iPhone: từ chối quyền, denied forever, GPS off, quyền gần đúng, quyền chính xác; cấp quyền rồi marker cập nhật. App không xin Always/background location.
5. Chọn điểm đến, tính tuyến ô tô thật, alternatives khi API trả, ETA/distance/delay/timestamp. Motorcycle phải bị chặn ở UI và backend.
6. Chạy hành trình khi ứng dụng foreground (người kiểm thử không trực tiếp thao tác khi lái), kiểm tra heading, lệch tuyến, refresh/proposal/cooldown. Background/end phải ngừng stream. ETA active route hiện là snapshot; ETA refresh là proposal riêng, không tự thay tuyến.
7. PostgreSQL thật: migrate fresh DB, kiểm tra FK cascade, ownership JWT và /me deletion. Chưa có login/sync UI; dùng token phát bởi auth service tin cậy để kiểm tra endpoint.
8. Codemagic unsigned compile/archive, rồi signing hợp lệ, cài iPhone, kiểm tra plugin và quyền. Ghi rõ artifact, commit, runner, logs, ngày test và thiết bị; không suy ra thành công chỉ từ YAML.
