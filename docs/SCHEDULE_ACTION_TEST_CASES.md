# Kết quả kiểm thử ngoại lệ lịch và thao tác thông báo

Đã chạy lại: **31 test backend + 12 test Flutter nghiệp vụ + 2 test layout = 45 test đạt**.

Dữ liệu lịch trong test là dữ liệu mô phỏng tách biệt, không phải lịch sử di chuyển thật. Không sửa tài khoản admin, không gọi API routing live. Restart ở đây là tạo lại worker trên cùng database, không phải khởi động lại máy Windows.

| Case | Thao tác | Kết quả quan sát | Trạng thái |
|---|---|---|---|
| TC01 | Hôm nay nghỉ; tạo lại worker | Ngày 26/10 bị bỏ qua; 27/10 vẫn planned; không nhắc ngày nghỉ; 0 request routing. | PASS |
| TC02 | Đổi giờ riêng một ngày | Đến 08:30, ETA 25 phút, chuẩn bị 20, dự phòng 10 → chuẩn bị 07:35, xuất phát 07:55; ngày khác vẫn 07:30. | PASS |
| TC03 | Khôi phục và gửi lặp | Khôi phục về giờ tuần 07:30; gửi cùng thay đổi hai lần không tăng revision. | PASS |
| TC04 | Lịch qua nửa đêm | Đến 00:15 → xuất phát 23:40, chuẩn bị 23:25 ngày trước. | PASS |
| TC05 | Dữ liệu sai / ngày ngoài lịch / quyền sở hữu | Giờ 25:00, ngày quá khứ, ngày không lặp: 422; tài khoản khác: 404; chuyến hoàn thành: 409. | PASS |
| TC06 | Ngoại lệ xa 100 ngày | Lưu/reset tồn tại bền vững; sửa lịch tuần không làm mất ngoại lệ; payload thông báo cũ bị hủy. | PASS |
| TC07 | ETA thay đổi / request đang chạy | ETA 40 phút, chuẩn bị 20, dự phòng 5 → xuất phát 06:45, chuẩn bị 06:25; bỏ kết quả ETA cũ khi ngoại lệ vừa được sửa. | PASS |
| TC08 | Nhắc lại 5 phút, bấm lặp và restart | Giữ nguyên giờ xuất phát; chỉ một sự kiện con; tạo lại worker trên cùng DB vẫn xử lý đúng; 0 request routing. | PASS |
| TC09 | Không còn đủ 5 phút / đã quá giờ đến | Còn 4 phút không cho snooze; đã qua giờ đến không cho start; trả 409 và dữ liệu không đổi. | PASS |
| TC10 | Xuất phát / bỏ qua từ thông báo | Start → in_progress; Skip → skipped; bấm lại không tạo hiệu ứng trùng; đã hoàn thành không được start lại. | PASS |
| TC11 | Tắt lịch / sự kiện nhắc lại chưa đến giờ | Hủy nhắc đang chờ; không xử lý nút của sự kiện tương lai trước giờ; tài khoản khác không đọc được. | PASS |
| TC12 | Thông báo Android — mock platform | Gửi đủ 3 action; zonedSchedule một lần; skip gọi cancel; pending được xóa. | PASS |
| TC13 | Bấm nội dung mở đúng chiều về | Mở đúng SavedTrip inbound, đúng occurrence inbound-today; không tự bắt đầu khi chỉ bấm xem. | PASS |
| TC14 | Offline / payload tài khoản khác | Request lỗi được báo lỗi, không giả thành công; payload sai tài khoản hoặc không hợp lệ bị bỏ qua. | PASS |
| TC15 | Form ngoại lệ Flutter | Nút nghỉ/đổi/reset chỉ gửi path của một ngày; không gửi lại weekdays và không đổi đối tượng lịch tuần. | PASS |
| TC16 | Layout sáng/tối và chữ lớn | 390px light và 320px dark chữ 200%; không có lỗi framework/tràn layout; cuộn tới các nút được. | PASS |


Chi tiết log, ảnh và JSON kết quả ở `build/reports/schedule-actions-qa/` (không commit dữ liệu build).

Các case native chỉ mock platform; vẫn cần test Android/iOS thật, GPS, quyền thông báo và nền/khóa màn hình. FCM/APNs chưa được xác minh.
