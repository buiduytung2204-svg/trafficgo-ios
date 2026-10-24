# Smart Departure trên Windows

## Trạng thái và giới hạn

Backend lưu lịch và sự kiện độc lập với Flutter. Worker là tiến trình riêng,
không tự khởi động trong FastAPI lifespan, nên reload/multiple HTTP workers
không tạo scheduler trùng. Đóng Flutter không dừng engine nếu worker Windows
vẫn chạy. Máy ngủ, tắt hoặc worker dừng thì không có kiểm tra mới; khi chạy lại,
worker đọc dữ liệu bền vững, không phát lại mọi lời nhắc cũ đã quá giai đoạn.

**Thông báo trên điện thoại khi app đóng chưa được triển khai.** Hiện có hộp thư
trong DB, polling khi app hoạt động và local notifications Android/iOS khi đã
cấp quyền, app đang nhận sự kiện. Web hiển thị hộp thư; không có web push.
FCM/APNs chưa cấu hình, `push_configured=false`. Không có hosting hay phí mới.

## Database và nâng cấp

Model hiện có `users`, `saved_places`, `saved_routes`, `route_checks`,
`user_settings` được giữ nguyên. Migration `002` chỉ thêm:

- `commute_schedules`: cấu hình lịch, owner, revision; giữ tham chiếu route nếu có.
- `commute_occurrences`: một chuyến cho một lịch/ngày đến, unique(schedule,date).
- `notification_events`: hộp thư, đọc/chưa đọc, trạng thái delivery,
  unique(occurrence,kind) chống trùng qua restart.
- `commute_installations`: credential ngẫu nhiên cho từng thiết bị khách, DB chỉ lưu SHA-256.
- `push_device_tokens`: owner, platform, active; không trả token trong API.
- `departure_worker_state`: lease, heartbeat, quota ngày và Retry-After bền vững.

PostgreSQL cấu hình trước đó trên máy không kết nối được. Phiên làm việc này đã
giữ bản cũ ở `backend/.env.before-smart-departure` (Git bỏ qua) và đặt
`DATABASE_URL` trong `.env` thành file SQLite **đường dẫn tuyệt đối**
`backend/trafficgo-local.db`. Không xóa/chuyển dữ liệu PostgreSQL cũ. Tuyến và
địa điểm SharedPreferences trên Flutter không bị thay đổi. Có thể dùng cùng
model/migration cho PostgreSQL sau này; chuyển dữ liệu SQLite sang PostgreSQL
là thao tác riêng có backup, chưa thực hiện tự động.

Backup file SQLite khi đã dừng API và worker; bảo vệ file vì có điểm đi/đến và
device token. Không commit DB, credential hoặc file `.env`.

## Chạy Windows

Mở terminal ở thư mục project; không chạy từ thư mục khác với env không đúng.

Terminal 1:

```powershell
cd backend
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Terminal 2:

```powershell
cd backend
.\.venv\Scripts\python.exe -m app.departure.worker
```

Worker kiểm tra DB mỗi 30 giây. Có thể kiểm tra một lượt bằng `--once`.
Dừng bằng Ctrl+C. Chỉ cần một worker; worker thứ hai không xử lý khi lease
còn hiệu lực. Lease DB 120 giây tự hết hạn sau crash; graceful shutdown nhả
lease ngay. SQLite dùng `BEGIN IMMEDIATE` cho transaction ghi ngắn, bật
foreign keys, busy timeout 5 giây. Không giữ transaction trong lúc chờ routing.
PostgreSQL dùng row lock khi thay đổi lịch/chuyến.

Không tự cài Windows Service/Scheduled Task. Có thể cấu hình Task Scheduler
sau: executable Python trong `.venv`, arguments `-m app.departure.worker`,
"Start in" là đường dẫn `backend`, không cho phép chạy instance mới khi
instance cũ còn hoạt động. Không cần quyền quản trị để chạy hai terminal.

## Chính sách ETA và quota

`.env.example` để live routing **tắt mặc định**:

```dotenv
DEPARTURE_LIVE_ROUTING_ENABLED=false
DEPARTURE_DAILY_ROUTING_LIMIT=24
```

Trên máy hiện tại live đã được bật có giới hạn 24 lần thử/ngày UTC. Worker
dùng trực tiếp Valhalla hiện có, không fallback TomTom. Không gọi provider từ
timer Flutter hoặc từ HTTP tạo/sửa lịch. Giới hạn này riêng với quota map/search.

- Bắt đầu kiểm tra trước giờ đến 90 phút, mở rộng theo chuẩn bị/dự phòng và
  ETA dài để không bỏ lỡ lịch qua nửa đêm.
- Cách giờ xuất phát >60 phút: 30 phút/lần; >30 phút: 20 phút/lần;
  gần hơn: 15 phút/lần. Toàn worker cách hai request ít nhất 60 giây.
- Tối đa 6 lần thử/chuyến, 24 lần/ngày toàn worker; đếm **trước** request,
  kể cả thất bại, lưu qua restart. Không tự reset file để tăng quota.
- Timeout tổng 12 giây, không retry tức thì. 429 tôn trọng Retry-After
  (giây hoặc HTTP date), chờ ít nhất 15 phút; giữ ETA gần nhất khi lỗi.
- ETA tăng >=3 phút hoặc >=15% phát `eta_increased` và `leave_earlier` nếu
  phù hợp, mỗi loại một lần/chuyến. ETA giảm vẫn dời giờ đề xuất về sau.
- ETA Valhalla không có traffic realtime. ETA nhập tay chỉ là ước tính ban đầu,
  có nhãn riêng và không giả làm kết quả provider.

## Công thức và vòng đời

`departure = arrival - ETA - buffer`; `prepare = departure - preparation`.
07:30, ETA25, buffer10, prepare15 → 06:40 chuẩn bị, 06:55 xuất phát.
Giờ đến gắn với **ngày đến** ở Asia/Ho_Chi_Minh; chuẩn bị có thể thuộc hôm trước.
Thứ 2=0 ... Chủ nhật=6. Hỗ trợ lịch một lần bằng `one_off_date`.

Mỗi lịch có nhiều occurrence, không dùng một status chung cho mọi tuần.
Lịch tắt không gọi provider/tạo sự kiện. Chuyến completed/skipped/cancelled/missed
không tính lại. Sửa lịch tăng revision; ETA trả về từ request với revision cũ
không được áp dụng. Completed trong lúc chờ API cũng được bảo vệ.
Lịch đã đến giờ đến mà chưa hoàn thành chuyển missed; không tự coi là đã đi.

Lời nhắc sắp chuẩn bị/sắp đi dùng khoảng 5 phút. Sau restart, chỉ phát loại
phù hợp giai đoạn hiện tại, không phát hàng loạt các mốc đã lỡ.

## Kiểm tra từ đầu đến cuối trên web

1. Chạy API + worker như trên. Dùng bản web mới tại `http://localhost:5173`, Ctrl+F5.
2. Giữ access token backend đã thiết lập trong Cài đặt. Mở thẻ "Lịch nhắc giờ
   xuất phát" trên trang chủ hoặc Cài đặt. Bấm "Kết nối lịch nhắc" một lần.
   App tạo identity khách riêng và lưu credential trong secure storage.
3. Bấm Tạo lịch. Chọn tuyến đã lưu hoặc hai địa điểm, đặt phương tiện, ngày
   lặp hoặc ngày một lần, giờ đến, chuẩn bị/dự phòng. Có thể nhập ETA25 để
   kiểm tra ngay công thức, với nhãn "Ước tính bạn nhập".
4. Lưu; xem trạng thái đồng bộ, giờ chuẩn bị/đi, ETA source, timestamp và
   heartbeat. Gần chuyến đi worker tự cập nhật, trong giới hạn bên trên.
5. Để thử lời nhắc nhanh mà **không gọi API**, dùng mô phỏng bên dưới. Đối với
   lịch thật, đặt ngày hôm nay và giờ đến gần hiện tại, đừng tạo nhiều lịch
   chỉ để kích hoạt provider. Mở Lịch sử thông báo; bấm sự kiện để đánh dấu đã
   đọc và mở tuyến đã lưu (không tự bắt đầu GPS/navigation).
6. Đóng Flutter: worker vẫn ghi sự kiện. Mở lại và đồng bộ để xem hộp thư.
7. Dừng API: app chuyển trạng thái mất kết nối sau lần poll (30 giây) hoặc
   bấm Đồng bộ; không cho ghi và vẫn xem bản lưu. Tuyến/địa điểm cục bộ còn nguyên.
8. Restart worker/API: lịch, hộp thư, credential và quota còn trong DB. Bỏ qua
   hoặc hoàn thành một chuyến để kiểm tra không có nhắc mới cho chuyến đó.

Xóa lịch có xác nhận sẽ xóa occurrence và sự kiện liên quan. Nút "Xóa dữ liệu
lịch nhắc của tôi" xóa lịch/thông báo/device token/credential của identity đó,
không xóa tuyến hay địa điểm cục bộ. Mất credential không thể nhận lại danh tính
khách chỉ bằng tên; đăng nhập/khôi phục tài khoản là giai đoạn sau.

## Mô phỏng không tiêu thụ API

```powershell
cd backend
.\.venv\Scripts\python.exe -m app.departure.simulate --scenario all
```

Chọn riêng: `eta-increase`, `eta-decrease`, `five-minutes`, `departure-now`,
`late`, `offline`, `restart`. Fake clock chạy nhanh; ETA 15/25/40/60 phút.
Mỗi lần dùng database tạm riêng `trafficgo-simulation-*`, tự dọn sau khi chạy,
output gắn `SIMULATION_ONLY`; không có endpoint giả lập trộn vào production.

## API và bảo mật

OpenAPI ở `/docs`, nhóm Smart departure. Tất cả endpoint yêu cầu X-App-Token;
các endpoint cá nhân còn yêu cầu X-Schedule-Token riêng installation. Credential
được cấp qua `POST /api/v1/departure/session`; không dùng shared app token làm owner.

- `GET /overview`: lịch, occurrence kế tiếp, 100 thông báo gần nhất, heartbeat.
- `POST /schedules`, `PUT /schedules/{id}`, `DELETE /schedules/{id}`.
- `GET /schedules/{id}/occurrences`: lịch sử 30 chuyến.
- `PATCH /occurrences/{id}`: skipped/completed/cancelled.
- `PATCH /notifications/{id}/read`.
- `POST /devices`, `DELETE /devices/{id}`: chuẩn bị token Android/iOS; không gửi push.
- `DELETE /personal-data`: xóa dữ liệu lịch của chính owner.

Scope là `/api/v1/departure`. Owner khác nhận 404; không nhận quyền từ user_id
do client gửi. Không log credential/token, nội dung payload hoặc tọa độ.
Production cần HTTPS và account provisioning thực sự; chưa deploy.

## Chuẩn bị FCM/APNs

`PushNotificationProvider.send(token,payload,idempotency_key)` là interface;
`deliver_push` là hook chưa nối vào worker. Token invalid được deactivate;
idempotency key là event.id + device.id. Adapter tương lai phải deduplicate
và quản lý retry/outbox. Không hứa exactly-once remote delivery qua crash.
Firebase Admin, APNs capability, provisioning, Flutter messaging/background
handlers và thử nghiệm thiết bị thật còn thiếu. Không tạo credentials giả.

## Kiểm thử

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest -q
cd ..\mobile
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub --dart-define=BASE_MAP_SOURCE=geoapify --dart-define=API_BASE_URL=http://localhost:8000
```

Trên máy này có thể chạy Flutter từ junction ASCII
`C:\Users\tungb\trafficgo-work` để tránh lỗi analyzer với đường dẫn Unicode.

Tài liệu tham khảo:
[SQLite transactions](https://www.sqlite.org/lang_transaction.html),
[SQLAlchemy SQLite](https://docs.sqlalchemy.org/en/20/dialects/sqlite.html),
[flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications).
