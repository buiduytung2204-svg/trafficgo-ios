# Ngoại lệ lịch lặp và thao tác thông báo

## Cách sử dụng

Vào **Hành trình → Lịch nhắc**, chọn **Nghỉ / đổi giờ một ngày**:

- Mặc định chọn hôm nay theo múi giờ Việt Nam; có thể chọn một ngày khác trong năm tới thuộc lịch lặp.
- **Đổi giờ ngày này** chỉ đổi giờ cần đến của lần đi đó. ETA gần nhất được giữ, giờ chuẩn bị/xuất phát được tính lại.
- **Nghỉ / bỏ qua ngày này** không tắt lịch tuần và không xóa lịch sử.
- **Khôi phục theo lịch tuần** gỡ ngoại lệ của ngày chưa bắt đầu; không khôi phục chuyến đã hoàn thành/hủy/đã qua giờ đến.
- Mở **Ngoại lệ đã lưu** để xem tối đa 14 ngoại lệ gần nhất của lịch.

Hộp thư thông báo và thông báo hệ điều hành có ba thao tác:

- **Xuất phát**: đánh dấu lần đi đang di chuyển, mở đúng chiều hành trình và khởi động luồng dẫn đường hiện có khi tìm được tuyến và được cấp quyền GPS. Nếu GPS/routing lỗi, màn bản đồ hiển thị lỗi để xử lý; không tự ghi nhận hoàn thành chuyến.
- **Nhắc lại sau 5 phút**: giữ nguyên giờ xuất phát, lưu mốc nhắc lại và một sự kiện con có ID ổn định trong database. Khi thiết bị hỗ trợ và đã cấp quyền, hẹn thêm thông báo cục bộ bằng `zonedSchedule`. Android dùng lịch không chính xác `inexactAllowWhileIdle`, không xin quyền exact alarm; hệ điều hành có thể trì hoãn.
- **Bỏ qua hôm nay**: bỏ qua ngày của lần đi gắn với thông báo (quan trọng khi chuẩn bị từ tối hôm trước), không bỏ qua cả tuần.
- Bấm phần nội dung thông báo: mở đúng điểm đi/đến, phương tiện, chiều và ID lần đi; ưu tiên geometry đã lưu nếu khớp hành trình.

Các nút native được cấu hình mở ứng dụng ở foreground để xác thực và gọi backend. Không chạy HTTP từ background isolate. Hộp thư web có các thao tác tương đương; web không có thông báo native.

## Lưu trữ và API

Không thêm bảng trùng hoặc xóa dữ liệu. Dùng các cột JSON đã có của `commute_occurrences` và `notification_events`, vì vậy không có thay đổi cấu trúc bảng cần Alembic migration:

- `day_override`: giờ đến/thời gian chuẩn bị/dự phòng riêng (API hỗ trợ cả ba; UI hiện cho đổi giờ đến).
- `exception_revision`: chặn ghi ETA cũ từ request đang chạy, phân biệt lần nhắc sau khi sửa giờ riêng.
- `snooze_until`, `snooze_source`: mốc nhắc lại bền vững.
- `action_result`, `action_at`, `reminder_event_id`, `cancelled`, `scheduled_for`: xử lý và hủy nhắc idempotent.
- Trạng thái `in_progress`: đã chọn xuất phát; chỉ hoàn thành qua thao tác xác nhận chuyến hiện có.

API cần cùng xác thực hiện tại (`X-App-Token` nếu bật và session `X-Schedule-Token`):

- `PUT /api/v1/departure/schedules/{id}/exceptions/{YYYY-MM-DD}` với `action=skip|change|reset`, `arrival_time=HH:mm` khi đổi giờ.
- `GET /api/v1/departure/notifications/{id}` để giải quyết đường dẫn thông báo kể cả ngoài 100 sự kiện trong overview.
- `POST /api/v1/departure/notifications/{id}/action` với `action=start|snooze|skip`.

Unique constraint `(occurrence_id, kind)` và khóa transaction hiện có chống nhắc trùng. Cùng thao tác trên cùng thông báo trả lại kết quả; thao tác khác hoặc chuyến đã kết thúc trả 409. Payload native gắn namespace tài khoản, không chứa token hay tọa độ. Server luôn kiểm tra quyền sở hữu.

## Chạy và kiểm tra trên Windows

Chạy backend và **một** worker theo hướng dẫn Smart Departure hiện có; restart cả hai để nạp code mới. Không tăng quota hay tạo request routing khi thao tác skip/snooze. Worker vẫn giữ giới hạn request cũ.

1. Tạo lịch lặp ngày mai, ETA 25 phút, cần đến 07:30, chuẩn bị 15, dự phòng 10.
2. Đổi riêng ngày mai thành 08:30: chuẩn bị 07:40, xuất phát 07:55. Các ngày khác vẫn 07:30.
3. Bỏ qua ngày mai, refresh/restart backend: vẫn bỏ qua. Khôi phục: trở lại giờ tuần.
4. Để worker phát một sự kiện gần giờ chuẩn bị/xuất phát; thử nút nhắc lại. Chỉ có một sự kiện con sau năm phút, giờ xuất phát không đổi.
5. Thử xuất phát rồi xác nhận hoàn thành; thông báo cũ không được khởi động lại chuyến đã hoàn thành.
6. Trên Android/iOS đã cấp quyền, kiểm tra ba nút, mở đúng chiều và nhắc lại khi đưa app ra nền. Đây là bước cần thiết bị thật, chưa được chứng nhận bằng unit test.

Kiểm thử tự động dùng database tách biệt, đồng hồ giả và FakeRouting; không sửa tài khoản admin hoặc tiêu thụ API live. Xem `backend/tests/test_departure_exceptions.py` và `mobile/test/departure_actions_test.dart`.

## Giới hạn

FCM/APNs chưa cấu hình. Những sự kiện mới trên backend khi Flutter đóng hoàn toàn vẫn chưa được đẩy về máy. Một nhắc lại đã hẹn cục bộ có thể do OS hiển thị mà không cần polling, nhưng chưa kiểm thử thiết bị thật; không cam kết đúng giây hoặc hoạt động sau force-stop/reboot. Nếu bỏ qua/tắt/xóa lịch từ thiết bị khác trong lúc máy đang offline, thông báo cục bộ cũ chỉ được hủy khi máy đồng bộ lại. Backend không chấp nhận thao tác trên sự kiện đã hủy/hết hạn.
