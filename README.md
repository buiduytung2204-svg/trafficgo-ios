# TrafficGo

Flutter + FastAPI cho bản đồ/giao thông Hà Nội, tập trung iPhone. Đã kiểm tra API TomTom thật cho map, traffic, tìm kiếm và tuyến ô tô; không dùng traffic giả. Cần API key riêng để chạy. Chưa kiểm thử trên iPhone hoặc chạy macOS CI/signing: **chưa đạt nghiệm thu iOS đầy đủ**.

## Chạy

1. Theo [Windows setup](docs/WINDOWS_SETUP.md), cài Flutter và backend dependencies.
2. Theo [API setup](docs/API_SETUP.md), tự cấu hình backend/.env (TomTom key, access token, PostgreSQL). Không commit secrets. Chạy migration trước khi dùng sync endpoint.
3. Backend: từ backend chạy `.venv/Scripts/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-access-log`. OpenAPI ở /docs, health ở /health.
4. Mobile: từ mobile chạy `flutter pub get`, `flutter run --dart-define=API_BASE_URL=https://YOUR_BACKEND`. Nhập app access token trong Cài đặt. Guest saved places hoạt động cục bộ, không cần account/database.
5. Dùng tìm kiếm hoặc nhấn giữ bản đồ, định vị GPS rồi tìm tuyến ô tô; chọn alternative nếu provider có. Xe máy bị khóa rõ ràng vì chưa xác minh.

## Tài liệu

- [Kiến trúc và giới hạn](docs/ARCHITECTURE.md)
- [Kiểm thử](docs/TESTING.md)
- [iOS CI](docs/IOS_BUILD.md), [IPA signing](docs/IPA_SIGNING.md)
- [Chi phí](docs/COST_ESTIMATION.md), [Tiến độ và việc còn lại](docs/PROGRESS.md)

Không có voice navigation, background tracking, đăng nhập/sync UI hoặc offline map. Tuyến thường dùng chỉ lưu hai điểm, khi chọn sẽ tính lại từ GPS. Limiter phù hợp một worker; bộ đếm ngân sách/ngày được lưu cục bộ qua restart. Triển khai backend public cần hard quota/gateway và authentication thiết bị. Không coi configured là provider verified.

Kiểm tra gần nhất: `flutter analyze` sạch, 18 Flutter tests và 16 backend tests đạt; build Web thành công. Cấu hình Codemagic có sẵn, chưa có IPA đã ký.
