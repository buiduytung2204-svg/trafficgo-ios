# Danh mục Honda Việt Nam và bảo dưỡng

Kiểm tra danh mục chính thức ngày24/10/2026. Chỉ lưu metadata/liên kết. Không phân phối PDF hay coi lịch bảo dưỡng là giống nhau giữa mọi đời xe.

Nguồn: https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung

| Dòng xe | Nhãn năm có tài liệu trên chỉ mục hãng | Năm chưa tìm thấy đúng nhãn |
|---|---|---|
| Wave Alpha | 2023, 2024 | 2020, 2021, 2022, 2025, 2026 |
| Wave RSX FI | 2023, 2024, 2026 | 2020, 2021, 2022, 2025 |
| Wave Alpha cổ điển | 2024, 2025 | 2020, 2021, 2022, 2023, 2026 |
| Vision | 2020, 2023, 2024, 2025, 2026 | 2021, 2022 |
| Future 125 FI | 2022, 2025, 2026 | 2020, 2021, 2023, 2024 |
| LEAD 125 | 2026 | 2020, 2021, 2022, 2023, 2024, 2025 |
| SH125i | 2021, 2023, 2024, 2026 | 2020, 2022, 2025 |
| SH150i | 2021 | 2020, 2022, 2023, 2024, 2025, 2026 |
| SH160i | 2023, 2024, 2026 | 2020, 2021, 2022, 2025 |
| SH350i | 2021, 2023, 2025 | 2020, 2022, 2024, 2026 |
| SH mode 125 | 2020, 2022, 2023, 2024 | 2021, 2025, 2026 |

## Phạm vi xác minh
- official_index_listing nghĩa là Honda liệt kê nhãn tài liệu và URL này; không có nghĩa đã xác minh tất cả nội dung PDF hoặc chu kỳ cho từng phiên bản.
- intervals_verified=false/full_schedule_verified=false cho toàn lịch; verified_items có engine_oil_replacement đối chiếu trực quan. trim_scope vẫn not_verified; không tự áp cho mọi bản Sport/tiêu chuẩn.
- Năm2020–2026 là dải người dùng có thể khai báo theo giấy tờ. Không khẳng định mọi dòng/dung tích/phiên bản được bán ở mọi năm; đặc biệt SH150/160 và Vision Sport phải đối chiếu thực tế.
- Vision có lựa chọn Tiêu chuẩn/Thể thao(Sport)/Khác; đây là khai báo của người dùng. Không tự áp tài liệu model lên riêng bản Sport.
- Trang Honda có điều khoản truy cập HDSD; ứng dụng mở trang hãng để người dùng xem và chấp nhận. Không bypass giao diện điều khoản bằng viewer PDF tích hợp.

## Chức năng
- Cài đặt hoặc menu bản đồ → Xe và bảo dưỡng. Thêm xe, chọn dòng/năm/phiên bản, nhập công-tơ-mét.
- Chỉ cập nhật số km từ công-tơ-mét; không cộng từ tuyến bản đồ hoặc tự suy ra từ hành trình. Không cho số km giảm trong cùng hồ sơ.
- Thêm mốc nhắc theo ngày hoặc số km; đến một trong hai mốc sẽ được đánh dấu đến hạn. Mốc sắp đến hạn mặc định hiển thị trong7 ngày hoặc100km là ngưỡng giao diện, không phải khuyến nghị kỹ thuật bảo dưỡng.
- Mốc thay dầu theo sách yêu cầu xác nhận mã/đời/phiên bản và nhập lịch sử km/ngày. Lần đầu1.000km, các mốc tổng6.000km (SH350:12.000km), hoặc hàng năm tùy mốc trước. Mốc nhập tay vẫn ghi Do người dùng thiết lập; không áp sách đời khác.
- Chỉ hiển thị nhắc khi mở ứng dụng/màn hình; chưa kết nối worker, FCM/APNs hay background notification cho bảo dưỡng.
- Xác nhận hoàn thành tạo lịch sử một lần, không tự tính mốc tiếp theo. Muốn lặp cần tạo mốc mới theo sổ xe.
- Nút Chi phí trong lịch sử mở form khoản chi thực tế mục Khác. Người dùng nhập tiền rồi xác nhận; cùng ID bảo dưỡng mở lại khoản chi để sửa thay vì nhân đôi.
- Dữ liệu garage.v1 trong SharedPreferences, versioned, ghi tuần tự/rollback khi lỗi; hồ sơ hỏng giữ nguyên và khóa ghi. Xóa xe xóa mốc nhắc nhưng giữ lịch sử và khoản chi. Chưa đồng bộ hồ sơ xe lên backend.

## Dữ liệu nguồn

### Wave Alpha
- [Wave Alpha 2024](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=114) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/P8qeKg7vdU5RIqpRvC4v.pdf)
- [Wave Alpha 2023](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=87) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/Q8CyLQGToNX5oKGbYW5x.pdf)

### Wave RSX FI
- [Wave RSX FI 2026](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=152) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/EzA6x0gXYsjvv9AhkVm2.pdf)
- [Wave RSX FI 2024](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=123) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/aRAQz3YRViMKvY1lWCUd.pdf)
- [Wave RSX FI 2023](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=95) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/hXJlUsmTa6v62szG78g5.pdf)

### Wave Alpha cổ điển
- [Wave Alpha phiên bản cổ điển 2025](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=129) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/PIcp8XLSxQmsi5X5Twsy.pdf)
- [Wave Alpha phiên bản cổ điển 2024](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=117) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/vdigdIhCeSx0yAGELhU3.pdf)

### Vision
- [Vision cổ điển 2024](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=120) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/t0ae7gUVJJb4r1UkHKrK.pdf)
- [Vision 2026](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=163) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/December2025/FgO9EU07CB768QM5Adl7.pdf)
- [Vision 2025](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=143) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/VTlZXWuAU6WYR0QTisGc.pdf)
- [Vision 2023](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=119) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/KV4oh5W47Rrx9qOoVIPW.pdf)
- [Vision 2020](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=118) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/VHp2KC4V1F29U9TVzmzW.pdf)

### Future 125 FI
- [Future 125 Fi 2026](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=158) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/October2025/4S8C4gHZTWoGUUdFaj0K.pdf)
- [Future 125 FI 2025](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=125) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/AoqkctECwilfhh3sNNxU.pdf)
- [Future 125 FI 2022](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=1&version=66) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/itn9YoNXl6STLMdBNUri.pdf)

### LEAD 125
- [LEAD ABS 2026](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=162) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/November2025/a1ImE0kmkoA3Vj3r5eVr.pdf)

### SH125i
- [SH160i/125i 2026](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=161) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/November2025/UG9NBoEDyF0DHrjoTphA.pdf)
- [SH160i/125i 2024](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=115) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/IRI1wKHmapsXwHcA9BRy.pdf)
- [SH160i/125i 2023](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=96) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/TQzPVhHHotbm0pssiUri.pdf)
- [SH150/125i 2021](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=58) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/Ti9DD1gkZnXDIPeZVYB1.pdf)

### SH150i
- [SH150/125i 2021](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=58) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/Ti9DD1gkZnXDIPeZVYB1.pdf)

### SH160i
- [SH160i/125i 2026](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=161) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/November2025/UG9NBoEDyF0DHrjoTphA.pdf)
- [SH160i/125i 2024](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=115) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/IRI1wKHmapsXwHcA9BRy.pdf)
- [SH160i/125i 2023](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=96) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/TQzPVhHHotbm0pssiUri.pdf)

### SH350i
- [SH350i 2025](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=142) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/R8BlCU6VrTkb1Zitb6V5.pdf)
- [SH350i 2023](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=98) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/wvvZIxuzSdpo44LlzsUX.pdf)
- [SH350i 2021](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=57) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/FaWYCDcJxZA7WBBmkhq8.pdf)

### SH mode 125
- [Sh mode 2024](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=121) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/LqBycQConAOw1xIB2JDJ.pdf)
- [SH mode 2023](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=93) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/mxqpo4kRgALNJk5iPtx7.pdf)
- [Sh mode 2022](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=73) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/XkqWr6zDGQt0KqEUDAYg.pdf)
- [Sh mode 2020](https://www.honda.com.vn/xe-may/dich-vu-sau-ban-hang/huong-dan-su-dung?category=2&version=48) — [PDF do hãng liệt kê](https://cdn.honda.com.vn/motorbike-manual/September2025/ipcSi61wzcQkWHMiFpw9.pdf)

## Đối chiếu và test mốc dầu24/10/2026

Đã đọc27PDF, đối chiếu hàng dầu/cột km/thay hàng năm bằng ảnh render; asset giữ trang và SHA256. Vision2025/2026 dùng loạiV ởPDF73; Future2022 dùng bảngPDF138 trong tài liệu gộp, yêu cầu đối chiếu mãJC764/JC765.

62kịch bản/310kiểm tra biên đạt; widget đổi trạng thái sau cập nhật công-tơ-mét, hàng năm/leap-day, lưới sau1.000km, xác nhận/sai năm và lịch sử nhiều chu kỳ. Chưa kiểm thử GPS ngoài đường hoặc OSnotification. Báo cáo trong build/reports; PDF hãng không commit.
