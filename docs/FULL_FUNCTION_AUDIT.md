# TrafficGo — kiểm tra toàn bộ chức năng hiện có

Ngày kiểm tra:24/10/2026. Chỉ làm việc trên source hiện tại, không tạo dự án mới, không push/deploy, không đổi credentials hoặc tăng quota.

## Kết quả tổng hợp

| Kiểm tra | Kết quả |
|---|---|
| Backend pytest |86/86 đạt; JUnit kèm trong gói báo cáo |
| Flutter analyze |Không có issue |
| Flutter test |106/106 đạt, tăng33test so với73test đầu lượt audit |
| Ma trận UI bổ sung |13màn hình ×2cấu hình =26test đạt |
| Web JavaScript build |Thành công43,9giây; không phải Wasm/Android/iOS build |
| iOS static config |Đạt kiểm tra plist/XML/project; chưa chạy Xcode |
| Python pip check |Không có dependency requirement bị hỏng; không phải quét CVE |
| Smoke backend thật |7/7request HTTP200; chi tiết live-smoke.json |
| Worker Windows |Heartbeat mới, lease đang hoạt động lúc kiểm tra |

Các cảnh báo backend:3deprecation warnings từ Starlette/TestClient/httpx và cấu hình Alembic path_separator; không phải test fail. Chưa thay dependency chỉ để tắt warning.

## Phạm vi chức năng

| Nhóm | Đã kiểm tra | Giới hạn |
|---|---|---|
| Tài khoản / cá nhân hóa |Đăng ký/login/session/owner, setup bắt buộc, bản nháp, retry, hai tài khoản, trạng thái kết nối |Chưa đồng bộ xe/geometry/chi phí giữa thiết bị; chưa email reset/MFA |
| Bản đồ |Camera khi pan/lỗi/refresh, cancellation/retry/429, shell iPhone, một tile Geoapify thật |Một tile200 không chứng minh toàn viewport/pan/zoom đều tải ổn trên mọi mạng |
| Tìm địa điểm |Debounce/cancellation/loading/empty/offline; NHS Trung Văn và CMC cơ sở2 trả tên phù hợp qua backend thật |Tên kết quả không tự chứng minh tọa độ/cổng trường đúng tuyệt đối |
| Routing ô tô/xe máy |Valhalla adapter/polyline/error/quota, alternative thật, giữ exact saved geometry; live car3tuyến, motorcycle1tuyến |Không xác nhận pháp lý mọi tuyến xe máy; ETA không traffic realtime |
| Điều hướng / đổi tuyến |ETA, threshold/cooldown, khoảng cách tới polyline, saved-origin; không tự ghi nhận chuyến khi chỉ mở bản đồ |GPS stream, heading, lệch tuyến ngoài đường và kết thúc/background cần thiết bị thật |
| Hành trình hai chiều |Chiều đi/về độc lập, lưu/khôi phục/sửa/xóa, completed-trip idempotency, giữ lịch sử tài chính khi xóa hành trình |Tab/scroll được test widget; chưa thao tác browser/điện thoại thật |
| Lịch nhắc thông minh |Công thức, timezone VN, qua ngày, lặp, ETA tăng/giảm, timeout/429, giới hạn request, lease, restart, terminal-state, không trùng event |Worker chạy không đồng nghĩa đã nhận push khi app đóng |
| Thông báo |Event/history/device-token contract, token invalid, idempotency |FCM/APNs + foreground/background delivery thật chưa được kiểm chứng |
| Địa điểm / cài đặt |Saved place/route persistence, theme, phạm vi lịch sử, dữ liệu riêng theo tài khoản |Không thay đổi dữ liệu thật khi test; hành động xóa trong UI chỉ mô phỏng hoặc kiểm tra nhãn |
| Chi phí / thống kê |CRUD, ngày thực, VND, tổng/ngày/tuần/tháng, bài test7ngày, grouping, lịch sử xác nhận |Dữ liệu automated tests được đánh dấu test, không đưa vào hồ sơ thật |
| Xe / bảo dưỡng |Km/date, mốc dầu đã xác minh, đúng năm/model hoặc không tự điền, idempotent completion, lịch sử và ghi chi phí có xác nhận |Không có auto GPS-odometer; không khẳng định đầy đủ mọi hạng mục của mọi xe |
| Bảo mật / quota / cache |Auth/owner, validation, timeout, Retry-After, budgets/cache/coalescing, không lộ key trong lỗi và bundle |Không phải penetration test hoặc kiểm thử tải production |
| Build |Web build thật và iOS static check |Không chạy Codemagic/Xcode/signing/IPA/Android native build trong lượt này |

## Lỗi mới đã tái hiện và sửa

| ID | Lỗi | Cách kiểm chứng sau sửa |
|---|---|---|
| F01 |JourneyStore notify sau dispose khi đổi tài khoản trong lúc đang lưu |Future hoàn tất, dữ liệu vẫn vào tài khoản cũ, tài khoản mới trống |
| F02 |GarageStore gặp cùng lỗi lifecycle, có thể rollback bộ nhớ sau khi ghi đĩa |Pending vehicle write hoàn tất và khôi phục đúng namespace |
| F03 |Ngày31/02 bị DateTime chuẩn hóa sang tháng3, làm sai thống kê |Chặn ngày không tồn tại, tháng0/13 và timestamp thay vì date; chấp nhận29/02 năm nhuận |
| F04 |Thông báo mất kết nối tài khoản không được xóa sau khi reconnect |Offline tạo lỗi; restore200 xóa lỗi |
| F05 |Chi tiết hành trình tràn dọc226px ở320px/chữ200% |NestedScrollView cho header và nội dung tab cuộn; ma trận UI đạt |
| F06 |Dropdown loại chi và chiều đi/về tràn ngang347/250px khi chữ lớn |Expanded dropdown, tên hành trình dài có ellipsis/tooltip; ma trận UI đạt |

Hai nội dung UI cũng được sửa: Cài đặt trước đây luôn ghi mặc định Ô tô dù hồ sơ là Xe máy; nhãn xóa cục bộ trước đây dễ bị hiểu là xóa mọi dữ liệu. Nay hiển thị đúng phương tiện và nêu rõ giữ xe, hành trình, chi phí, lịch nhắc. Không thực hiện xóa dữ liệu người dùng trong audit.

Bằng chứng4test fail trước sửa nằm trong flutter-regressions-before.log. Các lỗi layout đã được tái hiện bằng full_ui_matrix_test trước sửa, sau sửa26/26đạt. Các test cũ vẫn qua ở baseline; việc bổ sung test mới là lý do tìm được lỗi mà bộ cũ chưa bắt được.

## Kết quả gọi backend thật

- Health200.
- Traffic/status200 nhưng nội dung `status=unavailable`; provider=null. Đây là trạng thái trung thực, không phải traffic hoạt động.
- Search NHS Trung Văn200:1kết quả tên Nhà ở xã hội NHS Trung Văn (~2,375giây).
- Search CMC cơ sở2200:1kết quả tên Trường Đại học CMC (Cơ sở2) (~1,630giây).
- Car200:3tuyến, nhanh nhất6094m/1078s; provider=valhalla, traffic_aware=false (~3,341giây).
- Motorcycle200:1tuyến6094m/1096s; provider=valhalla, traffic_aware=false (~0,299giây).
- Một tile nền Geoapify200,36553bytes (~0,246giây).

Mỗi endpoint chỉ có một mẫu trong smoke này, không dùng các số trên làm p50/p95 hay cam kết độ ổn định. Có thể là cache hit.5request hướng provider qua backend (2search+2route+1tile), không suy ra số request upstream/credit; mọi guard/quota giữ nguyên. Không bật lại TomTom.

## Màn hình trong ma trận UI

Cài đặt; Địa điểm/tuyến đã lưu; Danh sách hành trình; Chi tiết hành trình; Chi phí/thống kê; Form chi phí; Xe/bảo dưỡng; Form mốc bảo dưỡng; Danh sách lịch; Form lịch; Lịch sử thông báo; Route planner; Đăng ký tài khoản.

Mỗi màn hình kiểm tra390×844/chữ100%/sáng và320×694/chữ200%/tối, cả ban đầu và sau cuộn.26ảnh render bổ sung nằm trong ui/. Đã xem các ảnh trọng tâm của hai lỗi layout và thống kê. Bộ onboarding có ma trận/ảnh riêng từ lượt trước. Ảnh dùng Roboto/Material Icons trong Flutter test; ký tự cần font fallback có thể khác trình duyệt thật.

## Những phần chưa thể kết luận

Browser inventory trong phiên trống, không có phiên browser để thao tác trực tiếp. Chưa đi đường/kiểm tra thiết bị thật, chưa FCM/APNs, chưa PostgreSQL thật, chưa macOS signing/build. Không thể kết luận tuyệt đối không còn bug từ automated tests. Không sửa hoặc tạo lịch/chi phí/xe của người dùng thật.

Bản Web sau sửa tại http://localhost:5173; Ctrl+F5 để tải lại. Backend/worker hiện có được giữ nguyên. Toàn bộ thay đổi vẫn chưa commit/push.
