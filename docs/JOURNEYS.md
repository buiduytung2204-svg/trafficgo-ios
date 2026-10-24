# Quản lý hành trình TrafficGo — bản Windows/local

Cập nhật 24/10/2026. Source được mở rộng trên nhánh `feature/smart-departure`.
Không push, deploy, bật gói trả phí hoặc thay credentials trong đợt mở rộng này.

## Chức năng và luồng sử dụng

Từ bản đồ, mở menu biểu tượng ô vuông cạnh tên TrafficGo:

1. **Địa điểm đã lưu**: thêm bằng tìm tên, GPS hoặc chạm bản đồ; nhấn giữ địa điểm để sửa tên, địa chỉ, phân loại và ghi chú. Chạm địa điểm để chọn nhanh làm điểm đến. Bộ chọn địa điểm cũng cho dùng điểm đã lưu làm điểm đi.
2. **Tìm tuyến giữa hai địa điểm**: chọn điểm đi/đến bằng tên, điểm đã lưu, GPS hoặc bản đồ. Đảo hai điểm sẽ xóa kết quả cũ và yêu cầu tính lại; không đảo polyline. Chọn ô tô/xe máy, tìm tuyến, chọn một kết quả thật, xem trên bản đồ rồi lưu.
3. **Hành trình đi học / đi làm**: tạo tên hành trình, chọn loại Đi học/Đi làm/Cá nhân. Trong hai tab Chiều đi/Chiều về, chọn riêng từng tuyến. Geometry, khoảng cách, ETA tham khảo, provider, timestamp và phương tiện được lưu riêng.
4. **Mở đúng tuyến đã lưu** không gọi routing để thay geometry. Tuyến cũ chỉ có endpoints vẫn đọc được, nhưng cần tính tuyến vì trước đây chưa lưu geometry.
5. **Thiết lập lịch nhắc cho chiều này**: kết nối backend nếu chưa có phiên, chọn ngày lặp/giờ đến/chuẩn bị/dự phòng. Với chiều về, giờ đến là giờ cần đến nhà. Hai chiều có lịch độc lập. Đổi tuyến đã liên kết lịch yêu cầu kết nối backend để cập nhật endpoints của lịch.
6. **Lịch nhắc** hiển thị giờ chuẩn bị/xuất phát, nguồn và tuổi ETA, trạng thái worker/đồng bộ. Worker hoạt động độc lập với Flutter. Tạm dừng hành trình sẽ tắt các lịch đã liên kết; muốn bật lại phải bật lịch cụ thể. Xóa hành trình giữ lại khoản chi và lịch sử chuyến.
7. **Tìm tuyến nhanh hơn / cập nhật ETA** trên bản đồ trả tuyến đề xuất. Xem trên bản đồ, chọn Giữ tuyến hoặc Xác nhận chuyển tuyến. Không ghi đè tuyến đã lưu; nút Lưu là thao tác riêng. Khi điều hướng, refresh tối đa mỗi 5 phút; đề xuất có ngưỡng >3 phút hoặc >15% và cooldown 5 phút. So sánh ETA còn lại dựa trên tiến độ geometry là ước tính, không phải số phút ùn tắc.
8. **Kết thúc hành trình** yêu cầu xác nhận đã hoàn thành trước khi tính thống kê. Mở bản đồ hoặc dừng dẫn đường không tự tạo chuyến hoàn thành. Completion có ID chống ghi trùng. Với lịch có occurrence, xác nhận đồng bộ trạng thái backend; khi lỗi kết nối hiển thị lỗi và cần thử lại từ Lịch nhắc.
9. **Thêm chi phí**: nhập khoản chi thực tế bằng VND, ngày, loại, hành trình/chiều và ghi chú. Có sửa/xóa. Không tạo chi phí tự động.
10. **Chi phí và thống kê**: ngày/tuần/tháng, phân nhóm loại/hành trình, biểu đồ 7 ngày, số chuyến xác nhận và trung bình chi phí/chuyến. Trung bình hiện dùng toàn bộ khoản chi chia số chuyến ghi nhận; không phải chi phí tự đo trên GPS.

## Dữ liệu bền vững và tương thích

- Giữ `saved`, `trips` trong SharedPreferences; các field bổ sung đều có default, tuyến cũ không bị xóa.
- `SavedTrip.route` giữ snapshot tuyến được chọn. `TravelRoute` thiếu metadata không mặc định là traffic-aware.
- Hành trình/chi phí/lịch sử dùng document version 1 ở khóa `journeys.v1` trên thiết bị/trình duyệt. Ghi tuần tự, đợi xác nhận lưu; lỗi ghi khôi phục trạng thái bộ nhớ. Document hỏng được giữ lại, khóa ghi để tránh ghi đè dữ liệu.
- Địa điểm, geometry và khoản chi hiện **lưu trên thiết bị**, chưa đồng bộ nhiều thiết bị. Xóa dữ liệu trình duyệt/gỡ ứng dụng có thể xóa dữ liệu này. Cần bổ sung export/import hoặc đồng bộ tài khoản trước sử dụng dài hạn.
- Lịch/occurrence/thông báo ở SQLAlchemy DB Windows. Migration `002_smart_departure` là additive, không xóa bảng cũ. `journey_id` và `direction` là field bổ sung trong JSON lịch hiện có, không tạo bảng lịch trùng.
- ID hành trình local là liên kết phục vụ cùng thiết bị, không phải chứng cứ phân quyền. Endpoint lịch kiểm tra credential per-install và owner như trước.
- Đổi nhiều lịch liên quan là nhiều HTTP request; nếu kết nối gián đoạn giữa chừng, xem lại các lịch trước khi sử dụng. Chưa có transaction xuyên backend và bộ nhớ điện thoại.

## ETA và nguồn dữ liệu

- Bản đồ và tìm kiếm: Geoapify, attribution Geoapify/OSM giữ trên giao diện.
- Routing: Valhalla. Xe máy tiếp tục dùng profile `motor_scooter` đã được người dùng chấp nhận cho bài tập. Không chứng nhận đầy đủ biển cấm/quy tắc địa phương; cần tuân thủ đường thực tế.
- Backend không khởi tạo TomTom, không dùng TomTom fallback. Endpoint tile TomTom cũ trả 410; mặc định Flutter Geoapify, cấu hình chọn TomTom bị từ chối. Adapter/test TomTom cũ còn trong source để tham chiếu hồi quy nhưng không nối với HTTP API/worker đang hoạt động.
- `TrafficDataProvider` độc lập, mặc định `UnavailableTrafficProvider`. Không có dữ liệu ùn tắc giả.
- Scheduler lấy ETA tuyến nhanh nhất thực sự do Valhalla trả từ hai đầu điểm và ghi `eta_basis=fastest_available_route`. Nó **không tính lại thời gian trên geometry cố định đã lưu** và không thay geometry đó. UI nói rõ điều này.
- Public Valhalla demo chỉ dùng phát triển; không có cam kết production/không giới hạn.

Nguồn chính thức đã xem:

- https://www.geoapify.com/terms-and-conditions/ — attribution OSM bắt buộc; Geoapify attribution cho Free; phải tuân thủ quota, không chia nhiều tài khoản để né quota.
- https://www.geoapify.com/ — cho phép cache/lưu kết quả theo điều khoản và nguồn dữ liệu; không bổ sung tải bản đồ offline hàng loạt.
- https://valhalla.github.io/valhalla/api/ — graph dựa trên OSM; không có bằng chứng demo hiện tại cung cấp traffic realtime tại Việt Nam.
- https://docs.here.com/traffic-api/docs/real-time-traffic-here-traffic-api-v7-concepts và https://www.here.com/learn/blog/expands-real-time-traffic-coverage-63-countries — HERE có sản phẩm/coverage Vietnam, nhưng chưa xác minh quyền sử dụng Free hiện tại với tài khoản này và chưa có credential. Trang pricing không đọc được trong phiên (HTTP403). Không bật dịch vụ hay khẳng định không có bất kỳ nguồn miễn phí nào khác.

## Hạn mức và lỗi

- Interactive routing mặc định 96 attempts/ngày UTC, SQLite `.routing-budget.db` giữ qua restart; cache RAM 60 giây, tối đa 64 kết quả, gộp cùng request, 2 upstream đang chạy và tối đa 8 tác vụ chờ/đang chạy.
- Upstream HTTP429 lưu Retry-After và chặn thử lại kể cả sau restart. Valhalla adapter nhận cả dạng số giây và HTTP date. Không retry ngay.
- Scheduler có quota riêng 24/ngày, tối đa 6/chuyến, giãn tối thiểu 60 giây và cập nhật 30/20/15 phút. Đây là giới hạn nội bộ cho thử nghiệm, không phải quota do Valhalla demo cấp.
- Geoapify vẫn dùng shared credit guard, cache/coalescing và tile retry có giới hạn của code cũ. Picker mới debounce650ms, hủy search cũ, đợi Retry-After và debounce tile250ms.
- Lỗi routing giữ tuyến/ETA tham khảo cũ; lỗi backend hiển thị chưa đồng bộ, không báo lưu thành công.

## Chạy trên Windows

Từ root project, terminal API:

```powershell
cd backend
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Terminal worker (chỉ một process):

```powershell
cd backend
.\.venv\Scripts\python.exe -m app.departure.worker
```

Terminal Web:

```powershell
cd mobile
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=BASE_MAP_SOURCE=geoapify
```

Nếu Flutter lỗi analysis server ở đường dẫn tiếng Việt, dùng junction `C:\Users\tungb\trafficgo-work` đã có trên máy này. Máy Windows phải hoạt động; điện thoại cần truy cập được địa chỉ LAN backend. Không dùng localhost trên điện thoại để chỉ máy tính.

Test không tiêu quota thật:

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m app.departure.simulate --scenario all
cd ..\mobile
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=BASE_MAP_SOURCE=geoapify
```

## Push và giới hạn nghiệm thu

Hộp thư DB, local notification khi Flutter đang nhận sự kiện, đăng ký/hủy device token, ownership, invalid token và idempotency interface đã có. Chưa cấu hình Firebase/APNs và chưa gửi push khi app đóng. Chưa thử GPS/notification trên thiết bị thật trong đợt này. Workflow Codemagic giữ nguyên, chưa chạy macOS CI cho các thay đổi này.
