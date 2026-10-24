# TrafficGo — 3 case kiểm thử cá nhân hóa (24/10/2026)

## Phạm vi và cách kiểm thử

Kiểm thử code Flutter thật bằng WidgetTester, ảnh render PNG với Roboto/Material Icons; HTTP địa điểm/routing là fixture riêng mang nhãn TEST, không phải dữ liệu realtime. Backend dùng FastAPI TestClient và database tạm. Không tạo tài khoản, hành trình, khoản chi trong database thật; không tiêu thụ quota provider.

Không có browser được kết nối trong phiên này (browser inventory trống, in-app browser unavailable). Vì vậy đây là kiểm thử nghiệp vụ + render tự động, chưa phải kiểm thử thao tác trên trình duyệt hoặc Android/iPhone thật. Ảnh QA dùng theme Material3 cùng màu chủ đạo của app; không dùng ảnh làm bằng chứng về bản đồ/provider thật.

## Case 1 — Hồ sơ đi học với Wave Alpha 2020

- Tên: Tùng kiểm thử. Chọn xe Wave Alpha2020 với công-tơ-mét5990km.
- Chọn Nhà/NHS Trung Văn và Đại học CMC cơ sở2 từ địa điểm TEST đã lưu (tọa độ mẫu, không dùng làm dữ liệu dẫn đường thật).
- Routing fixture trả hai phương án:30phút/8km và25phút/7,6km. Chọn phương án25phút.
- Lặp thứ2–6, cần đến07:30, chuẩn bị15phút, dự phòng10phút.
- Nhấn Hoàn tất hai lần liên tiếp trước khi UI kịp rebuild.
- Mong đợi: chỉ một POST setup; một hành trình gắn đúng lịch; giữ chính xác ID/geometry tuyến đã chọn; phương tiện motorcycle; backend tính chuẩn bị06:40 và xuất phát06:55; profile hoàn tất.
- Kết quả: ĐẠT sau sửa chặn bấm nhanh. Trước sửa test ghi nhận2POST; sau sửa chỉ1. Backend được kiểm tra công thức bằng dữ liệu lịch thực sự materialize trong database tạm.

## Case 2 — Đóng/mở lại, mất mạng và thử lưu lại

- Lưu nháp ở bước5 với tuyến đã chọn, sau đó mô phỏng backend không kết nối.
- Nhấn Hoàn tất: thông báo lỗi tiếng Việt, profile chưa hoàn tất; cờ onboarded chưa bật; draft vẫn còn.
- Hủy cây widget (mô phỏng đóng màn hình/app), tạo lại controller/store từ preferences đã lưu. Kết nối fixture trở lại rồi nhấn Hoàn tất.
- Mong đợi: quay lại đúng bước5, không mất route; hoàn tất thành công; một hành trình, một yêu cầu lưu thành công. Backend nhận lại cùng setup vẫn giữ một schedule_id. Đăng nhập bằng session mới vẫn đọc đúng lịch.
- Kết quả: ĐẠT. Đã chuyển việc bật trạng thái hoàn tất sang sau khi backend xác nhận. Restart kiểm thử là tái tạo controller/store và session mới; không phải tắt nguồn thiết bị thật.

## Case 3 — Hai tài khoản, màn hình nhỏ, chữ lớn và Dark Mode

- Tài khoảnA có xe,2địa điểm và chi phí xăng50.000đ. Đổi sangB: không thấy dữ liệu củaA. Quay vềA: xe/khoản chi vẫn giữ nguyên.
- Render đủ5bước setup ở320×694, chữ200%, Light và Dark Mode:10tổ hợp.
- Cuộn đến nút Tiếp tục/Hoàn tất và xác nhận nút nằm trong vùng màn hình ở từng bước; kiểm tra form thêm xe ở chữ lớn.
- Mong đợi: không có RenderFlex overflow/exception; nội dung dài có thể cuộn; không lẫn tài khoản; giá trị phiên bản xe dài có dấu ba chấm và tooltip để xem đầy đủ.
- Kết quả: ĐẠT. Đã sửa việc tên phiên bản dài bị cắt không rõ ràng, rút gọn nhãn Tên xe và thêm giải thích bên dưới. AppBar có thể rút gọn tiêu đề ở chữ200%; tiêu đề bước vẫn hiển thị xuống dòng, không mất chức năng.

## File và lệnh

- `mobile/test/personalization_cases_test.dart`:3case mới; ảnh chỉ ghi khi CAPTURE_UI=true.
- `mobile/test/personal_setup_test.dart`:4test nền đã có.
- `backend/tests/test_accounts.py`:6test tài khoản/migration/ownership/idempotency, bổ sung assert giờ chuẩn bị/xuất phát thực sự của occurrence.

```powershell
# Từ mobile
flutter test --no-pub test/personalization_cases_test.dart
flutter analyze --no-pub
flutter test --no-pub
# Sinh ảnh: thay đường dẫn font theo Flutter SDK của máy
flutter test --no-pub test/personalization_cases_test.dart --dart-define=CAPTURE_UI=true --dart-define=QA_FONT_PATH=C:/path/to/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf
# Từ backend
.\.venv\Scripts\python.exe -m pytest -q
```

Kiểm tra cuối: analyze sạch;73Flutter tests đạt;86backend tests đạt. Không tuyên bố đã kiểm thử GPS/push hoặc font/layout trong browser/thiết bị thật. Không push GitHub.
