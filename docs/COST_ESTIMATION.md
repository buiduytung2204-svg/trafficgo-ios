# Chi phí thử nghiệm

Chưa kích hoạt dịch vụ trả phí. Giá/quota phụ thuộc tài khoản và có thể thay đổi: xem API_SETUP.md với nguồn chính thức ngày 23/10/2026. Chưa có đơn giá vượt quota được xác minh, không dùng số cũ để cam kết chi phí.

Ước lượng nhu cầu (không phải hóa đơn): 20 phiên/ngày × 40 map tile × 30 ngày = 24K map request/tháng; 20 phiên × 40 traffic tile × 3 refresh × 30 = 72K traffic request; 20 phiên × 5 search × 30 = 3K search (vượt free Search v2 2.5K được niêm yết); 20 phiên × 5 route request × 30 = 3K routing. Pan/zoom và retry làm tăng số này.

Không bật overage; giảm search/session, quota cứng và ngắt dịch vụ khi hết hạn mức. Backend limiter không thay thế quota billing của provider. PostgreSQL local miễn phí phần mềm; cloud/Supabase, domain, HTTPS host, Codemagic runner và Apple Developer có điều kiện/quota/phí riêng. Chỉ bật dịch vụ có phí sau khi chủ tài khoản duyệt.
