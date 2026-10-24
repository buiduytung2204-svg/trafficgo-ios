> Cập nhật 24/10/2026: bản hiện tại dùng Geoapify cho map/search và Valhalla cho routing. TomTom không còn được khởi tạo trong API/worker; endpoint tile cũ trả 410. Các đánh giá TomTom bên dưới là lịch sử nghiên cứu. Xem [JOURNEYS.md](JOURNEYS.md) và [SMART_DEPARTURE.md](SMART_DEPARTURE.md) cho cấu hình/quota/giới hạn hiện tại. Chưa có nguồn traffic realtime được cấu hình.

# API validation — 23/10/2026

## Quyết định

MVP dùng TomTom Maps raster + Traffic Flow relative0 + Search v2 + Routing v1 qua FastAPI. Tất cả gọi HTTPS bằng API key backend. Chưa có key trong workspace: chưa kiểm chứng được response thật tại Hà Nội. Không có dữ liệu traffic giả. Bản đồ sẽ báo chưa cấu hình khi thiếu token/key.

- [TomTom Traffic coverage](https://docs.tomtom.com/traffic-api/documentation/tomtom-maps/v1/product-information/market-coverage) liệt kê Vietnam cho Flow và Incidents. Đây là coverage cấp quốc gia, không chứng minh mọi ngõ tại Hà Nội đều có dữ liệu hoặc độ trễ cụ thể.
- [Routing v1](https://docs.tomtom.com/routing-api/documentation/tomtom-maps/v1/calculate-route) có traffic=true, tối đa hai alternative trong request MVP; ETA có thể dùng traffic hiện tại và lịch sử. Chưa xác minh thực địa routing ô tô.
- Motorcycle là beta và restriction data không đầy đủ ở mọi vùng. Chưa tìm được bằng chứng đủ về tính hợp lệ xe máy tại Việt Nam: backend từ chối 422; UI ghi chưa hỗ trợ. Không chuyển tuyến car thành motorcycle.
- [Google coverage](https://developers.google.com/maps/documentation/routes/coverage) là nguồn kiểm tra hai bánh, nhưng trang đọc được chưa cung cấp bảng VN; chưa xác nhận trong phiên này. [Điều khoản Google](https://cloud.google.com/maps-platform/terms/maps-service-terms) không cho Routes content cùng non-Google map. Vì vậy adapter Google chủ động trả 501, không trộn vào TomTom map.
- [HERE coverage](https://docs.here.com/coverage/docs/here-coverage-information) và [Base Plan](https://www.here.com/get-started/pricing) cần kiểm tra riêng scooter/VN, use-case và quyền của tài khoản. HERE adapter trả 501. Chưa tích hợp.

## Giá và hạn mức

[Bảng giá TomTom chính thức](https://docs.tomtom.com/pricing) đọc ngày trên ghi free hàng tháng: raster map 200K, traffic raster 200K, routing 20K, Search API cũ 2.5K. Không dùng con số 50K tile/ngày và 2.5K request/ngày từ bài viết cũ. Bảng giá động không cung cấp được đơn giá vượt quota đáng tin cậy qua nội dung đọc trong phiên; cần xác nhận Pricing details và dashboard trước khi bật key. Giá Google có đối chiếu bên dưới; trang HERE pricing trả 403 khi mở nên chưa trích được đơn giá đủ điều kiện so sánh. Không tuyên bố bên nào miễn phí hoàn toàn.

Chỉ đăng ký plan miễn phí không tự nâng cấp/overage; đặt quota cứng trên dashboard. Backend mặc định giới hạn 2000 attempt-equivalent/ngày (mỗi operation dự trù 2 lần), 180 yêu cầu/phút/IP, một worker. Đây không phải billing meter bền vững: reset khi restart. Production cần giới hạn ở provider và Redis/gateway trước khi public. Tile có thể tiêu thụ hàng chục request một viewport. Search debounce 400ms; navigation refresh tối đa mỗi 90s theo GPS; traffic 120s khi foreground.

Bổ sung đối chiếu [bảng giá Google chính thức](https://developers.google.com/maps/billing-and-pricing/pricing): Compute Routes Essentials có cap miễn phí 10K/tháng, mức đầu sau cap $5/1000 event ($0.005/event); Pro 5K, $10/1000 ($0.01/event); Enterprise 1K, $15/1000 ($0.015/event), chưa tính thuế và tier volume. Cần xác định SKU theo tính năng traffic/two-wheeler, không mặc định áp Essentials. Stack TomTom không dùng các API này vì ràng buộc non-Google map. HERE/TomTom overage chưa xác minh được đơn giá động trong phiên, cần chủ tài khoản kiểm tra trước bất kỳ nâng cấp trả phí nào.

## Tile, màu và giấy phép

[Raster Flow Tiles](https://docs.tomtom.com/traffic-api/documentation/tomtom-maps/v1/traffic-flow/raster-flow-tiles) là PNG trong suốt 256/512, tương thích TileLayer flutter_map. Giữ nguyên relative0: xanh ≥.75, vàng .35–.75, cam .15–.35, đỏ <.15 tỷ lệ tốc độ/free-flow; đỏ sẫm biểu thị **đóng đường**, không tự gán là ùn tắc nghiêm trọng. Chú giải UI phản ánh điều này. Thời điểm nhận HTTP không phải thời điểm đo; raster không có timestamp quan trắc.

[TomTom terms](https://developer.tomtom.com/terms-and-conditions) phải được chủ tài khoản đọc và chấp nhận cho app/use case cụ thể. Trong phiên này chưa xác minh trọn vẹn quyền proxy tile và thời hạn lưu. Chưa cho phép phát hành production chỉ dựa vào code này. Không persist tile, traffic, geometry hay search result; response no-store, built-in disk cache flutter_map bị tắt. Chỉ lưu nhãn/tọa độ do người dùng chủ động chọn cho mục đích cá nhân; cần xác nhận quyền lưu nếu tọa độ bắt nguồn từ Search. UI lấy caption và full notices từ copyright endpoint qua backend, cho phép mở thông tin bản quyền trong bottom sheet; chưa kiểm thử response thật hoặc xác nhận yêu cầu logo/viewport notice trước phát hành. Không lấy điều khoản cache của Navigation SDK áp cho raster REST.

## Cấu hình

1. Tự tạo account TomTom, kiểm tra plan, product Maps/Traffic/Search/Routing và quota cứng. Không gửi key vào chat.
2. Copy backend/.env.example thành backend/.env. Điền TOMTOM_API_KEY và APP_ACCESS_TOKEN ngẫu nhiên đủ dài.
3. Chạy API như README; nhập access token trong Settings của app. Token của app không phải key provider; mobile binary/token có thể bị trích xuất. Production cần attestation, token cấp ngắn hạn, user/device quota và gateway.
4. Kiểm tra health, traffic tiles tại Hà Nội, tìm địa điểm, so sánh ba tuyến trên thiết bị. Không gọi trạng thái configured là verified.
5. Dùng HTTPS production. Trên iPhone localhost là chính iPhone: dùng hostname HTTPS của backend. Local HTTP chỉ dùng cho dev web/Android emulator theo cấu hình dev.
