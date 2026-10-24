# TrafficGo — Đen than + Lime

## Phạm vi
Màn tổng quan mới: lời chào từ hồ sơ, tìm kiếm thật, ba lối tắt theo phân loại địa điểm, thẻ lịch tiếp theo và bản đồ thật thu gọn. Bản đồ sử dụng cùng State/MapController khi mở toàn màn hình, thu về và chuyển tab. Không thay provider, database hoặc dữ liệu người dùng.

Theme Forui và Material dùng charcoal #20252B, nền #F5F6F2, lime #C6F36B, surface trắng. Font Be Vietnam Pro đóng gói cục bộ (Regular–ExtraBold), giấy phép SIL OFL trong mobile/assets/fonts/OFL.txt. Không thêm dependency runtime. Minh họa trường học được vẽ bằng CustomPainter, không cắt từ ảnh tham chiếu.

## Khác mẫu tham chiếu
Tên dài được xuống dòng thay vì cắt mất; chữ lớn chuyển thẻ sang bố cục dọc. Có ghi chú ETA chưa xét giao thông / chưa đồng bộ theo trạng thái thật. Logo Go dùng lime đậm hơn để đủ tương phản trên nền sáng. Không dựng status bar hoặc khung iPhone giả. Bản đồ và tuyến sử dụng dữ liệu thực tế nên khác đường trong mockup.

## Kiểm chứng
Ảnh trong build/reports/charcoal-lime/after là widget render với dữ liệu TEST cô lập, không ghi vào tài khoản thật. Widget tests không tải tile mạng; vùng nền bản đồ trống không phải screenshot tile thực tế. Không tuyên bố đã kiểm thử thiết bị iOS, độ mượt/FPS hoặc haptic thực tế. Chưa có video thiết bị.

Các test mới kiểm tra mở/thu cùng map state, giữ tâm/zoom, địa điểm đã lưu, thiếu địa điểm mở picker và trạng thái không có lịch không bịa ETA. Ma trận UI bao gồm 390 px sáng và 320 px chữ 200% tối. Log analyze/test/build được lưu trong build/reports/charcoal-lime.
