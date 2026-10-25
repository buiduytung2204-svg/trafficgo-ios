# iOS: nhắc cục bộ và GPS trong hành trình

## Phạm vi đã triển khai
- Backend overview cung cấp các occurrence tương lai đã materialize (không gọi routing thêm). Flutter đặt trước các mốc chuẩn bị/sắp chuẩn bị, xuất phát/sắp xuất phát theo ETA đã đồng bộ.
- Dùng giờ tuyệt đối từ backend Asia/Ho_Chi_Minh; lưu signature/id bền vững, thay lịch cùng ID khi ETA/giờ đổi và đối chiếu pending requests của OS sau restart.
- Hàng đợi chọn 56 mốc gần nhất, tối đa 4 snooze và 1 alarm kiểm tra, dưới giới hạn 64 pending notification iOS. Không tạo alarm lặp vô hạn. Mở app để đồng bộ/tái nạp các ngày tiếp theo.
- Bỏ qua/ngừng/xóa lịch: hủy mốc không còn hợp lệ ở lần đồng bộ. Đăng xuất/chuyển tài khoản/xóa dữ liệu: hủy notification thuộc scope đó. Không hủy notification không thuộc scope đang xử lý.
- Receipt ngăn banner từ polling bị trùng với mốc local đã đặt. Các nút iOS Xuất phát/Nhắc lại/Bỏ qua mở app, xác minh occurrence và ownership trên backend trước khi thay đổi. Tapping tuyến khi lỗi mạng có thể dùng bản lưu, có nhãn cảnh báo; không bỏ qua phản hồi 401/403/404/409 của server.
- Trang Lịch nhắc có trạng thái số mốc/hạn đã hẹn, cảnh báo hẹn thất bại, nút thử sau 1 phút và nút tắt/hủy nhắc trên thiết bị.

## GPS iOS
Khi bắt đầu hành trình, chọn Chỉ khi mở app hoặc Tiếp tục định vị nền. Chỉ lựa chọn thứ hai giữ stream khi khóa màn hình/chuyển app. AppleSettings bật chỉ báo nền, activity automotiveNavigation và background updates chỉ cho stream đang điều hướng. Một lần định vị/tìm địa điểm không bật nền.

Info.plist khai báo UIBackgroundModes/location; không xin Always và không theo dõi vị trí ngoài chuyến. Khi dừng, kết thúc hoặc dispose màn điều hướng: hủy stream. Trong nền chỉ cập nhật vị trí trong RAM, không animate map, gọi routing liên tục hoặc mở dialog. Đến gần đích trong nền: dừng GPS, chờ trở lại để hỏi xác nhận hoàn thành; không tự ghi chuyến hoàn thành.

Không hứa GPS tiếp tục sau khi người dùng force-quit hoặc iOS kết thúc process. App không ghi lịch sử GPS liên tục.

## Kiểm tra thực tế trên iPhone sau khi build IPA mới
1. Bật backend Windows và worker. Đăng nhập app, tạo lịch có ETA và giờ cần đến trong tương lai. Mở Lịch nhắc, Cho phép thông báo; kiểm tra số mốc đã hẹn khác 0.
2. Bấm Thử thông báo sau 1 phút, khóa màn hình. Alarm kiểm tra không phải một chuyến thật. Kiểm tra cả Notification Center nếu Focus/Summary hạn chế banner/sound.
3. Tạo mốc chuẩn bị/xuất phát gần (không chỉ thử snooze), đồng bộ rồi đóng app/khóa màn hình, chờ mốc. Có thể tắt kết nối backend sau khi hẹn để kiểm tra local delivery độc lập.
4. Mở lại, sửa giờ/ETA và đồng bộ; kiểm tra mốc mới thay mốc cũ. Thử nghỉ hôm nay, tắt lịch, xóa lịch; mốc cũ không được tiếp tục báo sau khi đồng bộ.
5. Thử Xuất phát/Nhắc lại/Bỏ qua từ notification; khi có mạng phải mở đúng chiều và occurrence, không thay tuyến đã lưu. Thử thiếu mạng: không được báo thay đổi lịch thành công khi server chưa xác nhận.
6. Bắt đầu dẫn đường, chọn nền, khóa màn hình và di chuyển thực tế, mở lại xem vị trí. Kết thúc chuyến, kiểm tra không còn chỉ báo theo dõi. Thử lại với Chỉ khi mở app để xác nhận stream dừng trong nền.
7. Thu hồi quyền vị trí/thông báo, đăng xuất rồi đổi tài khoản, restart app/điện thoại; xác minh cảnh báo và không rò nhắc của tài khoản trước.

## Windows
Từ backend: `.venv/Scripts/python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-access-log` và tiến trình riêng `.venv/Scripts/python.exe -m app.departure.worker`.
Không nâng quota hoặc bật dịch vụ mới; worker tiếp tục dùng các giới hạn đã cấu hình. Chưa thay đổi database schema, không migration phá dữ liệu.

## Giới hạn còn lại
- APNs/FCM chưa cấu hình: ETA hoặc lịch thay đổi trên backend khi app đang đóng không tự cập nhật alarm local; cần mở app và đồng bộ. Đây không phải push realtime.
- Quyền, Focus, Scheduled Summary và chính sách iOS ảnh hưởng cách/thời điểm hiển thị. Mock test không chứng minh delivery hoặc GPS nền trên thiết bị thật.
- Chưa chạy macOS/Xcode/signing trong phiên Windows này. IPA cũ không chứa thay đổi; cần build lại sau khi đưa source mới lên CI.

## Test tự động
`flutter analyze`, `flutter test`; `python scripts/check_ios_config.py`; backend `pytest`.
Test riêng: ios_background_test.dart (Darwin method channel, timestamps, reschedule, revoke, ownership, offline cache, cap), ios_navigation_lifecycle_test.dart (stream còn/dừng theo lựa chọn và lifecycle), backend test_departure_exceptions.py (upcoming occurrences, resolver ownership/time/dedup).

Tham khảo: https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates và https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app.
