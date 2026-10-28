# Đổi URL backend trong app

Cá nhân → Địa chỉ backend → nhập URL gốc → Kiểm tra kết nối và lưu.
Sau khi lưu, đóng hẳn rồi mở lại app (Web: tải lại trang). Không cần cài lại.
Các bản cài cũ cần cập nhật một lần để có màn hình này.

URL được lưu riêng trên thiết bị và ưu tiên hơn API_BASE_URL của bản build.
Nút dùng mặc định điền lại địa chỉ của bản cài; vẫn cần kiểm tra và lưu.
Chỉ HTTPS cho máy chủ ngoài Internet; HTTP dành cho localhost/LAN trong thử nghiệm.
Không thêm /health, access token, mật khẩu, query hoặc fragment vào URL.

Chỉ dùng máy chủ tin cậy: sau lần mở kế tiếp, thông tin đăng nhập và request API
sẽ đến địa chỉ mới. Kiểm tra health không gửi token, không theo redirect và có timeout.
Health hợp lệ không tự chứng minh máy chủ đáng tin cậy.

Không chuyển URL ngay dưới các request đang chạy, không tự chuyển session giữa
các host. Session được phân tách theo URL; sau đổi tunnel có thể cần đăng nhập lại.
Không xóa tuyến, địa điểm, tài khoản hoặc database local. Dữ liệu trên server phụ
thuộc backend thực sự được kết nối. URL tunnel tạm vẫn có thể hết hiệu lực.

Chưa thay đổi APNs/FCM hoặc quyền GPS; đây là cấu hình kết nối trên Flutter.
