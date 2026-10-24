# TrafficGo

Smart Departure chạy cục bộ trên Windows: xem [hướng dẫn lịch nhắc và worker](docs/SMART_DEPARTURE.md).
Hỗ trợ lịch lặp/một lần, ETA Valhalla, giờ chuẩn bị/xuất phát, hộp thư và đồng bộ
Flutter. Worker chạy riêng, lưu bền vững trong database; FCM/APNs chưa được cấu hình.
Nền bản đồ web hiện dùng Geoapify; ô tô và xe máy dùng Valhalla, ETA chưa có traffic realtime.

Flutter + FastAPI cho bản đồ/giao thông Hà Nội, tập trung iPhone. Đã kiểm tra API TomTom thật cho map, traffic, tìm kiếm và tuyến ô tô; không dùng traffic giả. Cần API key riêng để chạy. Chưa kiểm thử trên iPhone hoặc chạy macOS CI/signing: **chưa đạt nghiệm thu iOS đầy đủ**.

## Chạy

1. Theo [Windows setup](docs/WINDOWS_SETUP.md), cài Flutter và backend dependencies.
2. Theo [API setup](docs/API_SETUP.md) và [Smart Departure](docs/SMART_DEPARTURE.md), cấu hình backend/.env (provider keys, access token, SQLite trên Windows hoặc PostgreSQL). Không commit secrets. Chạy migration trước khi dùng dữ liệu backend.
3. Backend: từ backend chạy `.venv/Scripts/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-access-log`. OpenAPI ở /docs, health ở /health.
4. Mobile: từ mobile chạy `flutter pub get`, `flutter run --dart-define=API_BASE_URL=https://YOUR_BACKEND`. Nhập app access token trong Cài đặt. Guest saved places hoạt động cục bộ, không cần account/database.
5. Dùng tìm kiếm hoặc nhấn giữ bản đồ, định vị GPS rồi tìm tuyến ô tô/xe máy; chọn alternative nếu provider có. Xe máy dùng Valhalla motor_scooter; tuân thủ biển báo thực tế.

## Tài liệu

- [Kiến trúc và giới hạn](docs/ARCHITECTURE.md)
- [Kiểm thử](docs/TESTING.md)
- [iOS CI](docs/IOS_BUILD.md), [IPA signing](docs/IPA_SIGNING.md)
- [Chi phí](docs/COST_ESTIMATION.md), [Tiến độ và việc còn lại](docs/PROGRESS.md)

Không có voice navigation, background tracking, đăng nhập tài khoản đa thiết bị hoặc offline map. Lịch nhắc đồng bộ theo identity khách riêng từng thiết bị. Tuyến thường dùng lưu hai điểm; lịch nhắc giữ điểm xuất phát đã chọn. Limiter HTTP phù hợp một worker; scheduler chạy riêng và có lease database chống trùng. Triển khai backend public cần HTTPS và kiểm soát truy cập/chi phí phù hợp.

Kiểm tra gần nhất: `flutter analyze` sạch, 45 Flutter tests và 76 backend tests đạt; build Web thành công. Cấu hình Codemagic giữ nguyên, chưa có IPA đã ký hoặc FCM/APNs hoạt động.

## Audit hiệu năng trên nhánh riêng

Xem [báo cáo baseline và cải tiến](docs/PERFORMANCE_AUDIT.md), [số liệu HTTP trước sửa](docs/benchmarks/baseline-http.json) và [sau sửa](docs/benchmarks/after-http.json). Nhánh audit thêm Valhalla cấu hình được, nguồn nền OSM tùy chọn, metrics và giảm request traffic; TomTom vẫn là mặc định. Các tính năng mới không tự đăng ký dịch vụ, đổi key hoặc bật thanh toán. Kết quả kiểm tra mới nhất của nhánh audit được ghi trong PROGRESS.md.

## Hành trình, lịch nhắc và chi phí

Xem [hướng dẫn quản lý hành trình](docs/JOURNEYS.md) cho luồng chọn điểm bằng tên,
lưu đúng tuyến hai chiều, tạo lịch nhắc, xác nhận chuyến hoàn thành và ghi chi phí.
Bản đồ/tìm kiếm dùng Geoapify, routing dùng Valhalla; TomTom đã ngừng nối vào API.
ETA hiện chưa có traffic realtime. Lịch nhắc lưu ở backend Windows; hành trình và
chi phí lưu trên thiết bị. Push khi app đóng còn cần Firebase/APNs.

Danh mục Honda2020–2026 và hồ sơ/mốc bảo dưỡng do người dùng thiết lập đã có
trong **Xe và bảo dưỡng**. Xem [nguồn tài liệu và phạm vi xác minh](docs/VEHICLE_MAINTENANCE.md).
Chưa tự điền chu kỳ theo hãng hoặc gửi push bảo dưỡng khi ứng dụng đóng.

Hồ sơ cá nhân, tài khoản và thiết lập xe/lịch lần đầu: [docs/PERSONALIZATION.md](docs/PERSONALIZATION.md).

## Giao diện thống nhất

Xem [UI/UX redesign](docs/UI_REDESIGN.md): theme xanh ngọc light/dark, 4 tab giữ trạng thái bản đồ, Forui primary actions, calendar Shadcn, Wolt forms và FL Chart từ chi phí thật. Flutter/CI vẫn dùng 3.47.7.
