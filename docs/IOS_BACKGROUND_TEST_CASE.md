# Case kiểm thử: đi học, nhắc giờ và GPS nền

Ngày chạy lại: 25/10/2026. Dữ liệu dưới đây là kịch bản kiểm thử cô lập,
không được nạp vào tài khoản hoặc database thật. Không gọi API routing thật.

## Một kịch bản xuyên suốt

Lịch: Nhà → Trường, giờ cần đến 07:30, ETA 25 phút, dự phòng 10 phút,
chuẩn bị 15 phút, timezone Asia/Ho_Chi_Minh. Tuyến lấy từ fixture trong test.

| Bước | Thao tác | Kết quả cần có |
|---|---|---|
| 1 | Đồng bộ lịch và cho phép thông báo | Chuẩn bị 06:40; xuất phát 06:55. Bốn mốc: 06:35, 06:40, 06:50, 06:55. |
| 2 | Đồng bộ lại, khởi tạo lại notification service | Giữ các ID; không đặt thêm thông báo trùng. |
| 3 | ETA tăng từ 25 lên 40 phút, đồng bộ trước các mốc | Chuẩn bị 06:25; xuất phát 06:40. Bốn mốc mới: 06:20, 06:25, 06:35, 06:40. Thay mốc cũ bằng cùng ID. |
| 4 | Khóa màn hình sau khi đồng bộ | Cần iPhone thật xác minh iOS hiển thị các mốc đã đặt, kể cả backend mất kết nối. |
| 5 | Nhấn thông báo | Mở đúng tuyến đã lưu, đúng chiều và occurrence; không thay geometry bằng tuyến khác. |
| 6 | Nhắc lại sau 5 phút, sau đó bỏ qua hôm nay | Backend lưu snooze; bỏ qua hủy nhắc liên quan sau đồng bộ; không sửa cả lịch tuần. |
| 7 | Với chuyến khác còn hợp lệ, bắt đầu và chọn tiếp tục định vị nền | Stream dùng AppleSettings bật background và chỉ báo; vẫn có listener khi lifecycle paused. |
| 8 | Trở lại app, rồi đóng màn điều hướng | Không tạo stream thứ hai khi đã giữ stream; dispose hủy listener. |
| 9 | Lặp bước 7 với Chỉ khi mở app | Paused hủy stream; resumed tạo lại; dispose hủy. |
| 10 | Thu hồi quyền thông báo hoặc đăng xuất/chuyển tài khoản | Hiển thị trạng thái phù hợp; hủy alarm thuộc tài khoản cũ, không khôi phục nhầm từ hàng đợi cũ. |

Các nhánh snooze, skip và start chạy trên fixture riêng vì một occurrence đã bỏ qua
không được bắt đầu lại. Các mốc 07:30 ở bảng là giá trị mong đợi theo công thức;
test tự động dùng đồng hồ cố định, bao gồm trường hợp qua nửa đêm, không chờ giờ thật.

## Kết quả đã chạy

- Flutter: `flutter test test/ios_background_test.dart test/ios_navigation_lifecycle_test.dart test/departure_actions_test.dart --reporter expanded`: **20 đạt**.
- Backend: `.venv/Scripts/python.exe -m pytest tests/test_departure_exceptions.py -q`: **17 đạt**, một cảnh báo deprecation từ Starlette/httpx.
- `python scripts/check_ios_config.py`: **đạt**, chỉ kiểm tra cấu hình tĩnh, không phải build iOS.
- Log Flutter: `mobile/build/ios-background-recheck.log`.
- Log analyze: `mobile/build/ios-background-recheck-analyze.log`.

Đây là một kịch bản nghiệp vụ được kiểm tra bằng nhiều test unit/widget/API độc lập,
không phải một phiên end-to-end trên thiết bị. Method channel thông báo và GPS được mock.
Không ghi dữ liệu test vào tài khoản người dùng, không thay quota, không cấu hình push.

## Còn cần iPhone thật

Build IPA mới chứa source này, ký/cài được lên iPhone rồi kiểm tra bước 4,
thao tác notification trên màn khóa và di chuyển thật ở bước 7–9.
Kiểm tra Focus/Scheduled Summary và quyền thông báo/vị trí.
Không suy diễn từ test mock rằng GPS vẫn chạy sau force-quit.
APNs/FCM chưa cấu hình; thay đổi trên backend khi app đóng chưa tự đồng bộ alarm.
