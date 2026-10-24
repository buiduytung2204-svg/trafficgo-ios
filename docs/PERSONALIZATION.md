# Hồ sơ cá nhân và thiết lập lần đầu

## Luồng sử dụng

Người dùng cũ vẫn mở bản đồ và dữ liệu khách như trước. Vào Cài đặt → Tạo tài khoản / đăng nhập để tạo hồ sơ riêng. Với lần cài mới, Bắt đầu khám phá mở đăng ký/đăng nhập. Tài khoản mới phải hoàn thành 5 bước:

1. Tên hiển thị và mục đích: đi học, đi làm hoặc cá nhân.
2. Phương tiện. Xe máy chọn/thêm dòng xe, năm, phiên bản và số công-tơ-mét qua danh mục xe hiện có. Ô tô dùng lựa chọn phương tiện chung.
3. Nhà/điểm xuất phát và nơi thường đến bằng tìm kiếm tên, GPS, địa điểm đã lưu hoặc chọn bản đồ.
4. Tìm tuyến thật, chọn chính xác tuyến chiều đi. Chiều về là tùy chọn và được tính riêng.
5. Ngày trong tuần, giờ cần đến, thời gian chuẩn bị và dự phòng. Hoàn tất tạo hành trình cục bộ và lịch nhắc trên backend Windows.

Thông tin nháp được lưu theo tài khoản để tiếp tục khi mở lại. Chưa có tuyến hợp lệ hoặc backend chưa xác nhận lưu lịch thì chưa hoàn tất hồ sơ. ID hành trình cố định và endpoint setup idempotent ngăn tạo lịch trùng khi thử lại. ETA là ETA routing, không phải traffic realtime.

Sau thiết lập, bản đồ dùng phương tiện mặc định đã chọn; hành trình và lịch nhắc xuất hiện trong chức năng hiện có. Sửa xe tại Xe và bảo dưỡng; sửa tuyến/lịch tại Hành trình và chi phí. Không tự tạo lịch chiều về nếu chưa chọn giờ về.

## Tài khoản và dữ liệu

- Backend thêm bảng `accounts` bằng migration003, liên kết bảng users hiện có; không di chuyển/xóa dữ liệu khách.
- Username 3–40 ký tự ASCII, không phân biệt hoa/thường; mật khẩu10–128 ký tự. Băm scrypt N32768/r8/p3 với salt ngẫu nhiên16byte, so sánh hằng thời gian. Theo [OWASP Password Storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html). Không lưu mật khẩu plaintext, không echo input trong lỗi validation.
- Session riêng từng lần đăng nhập, token ngẫu nhiên chỉ lưu FlutterSecureStorage; backend chỉ giữ SHA256 token trong bảng installation hiện có. Shared app access token vẫn cần để bảo vệ backend; đây không phải mật khẩu tài khoản.
- Giới hạn10 lần đăng nhập/đăng ký/phút/IP trong một tiến trình. Chưa có reset mật khẩu, email verification, MFA hoặc thời hạn session. Bản này phục vụ thử nghiệm Windows; khi triển khai online cần HTTPS và bổ sung quản lý session phù hợp.
- Địa điểm, tuyến chính xác/geometry, xe, chi phí, lịch sử, cài đặt và cache nhắc tách bằng namespace `account:<user_id>:` trên thiết bị. Các khóa khách cũ giữ nguyên. Đăng xuất không xóa dữ liệu khách hay tài khoản khác; đăng nhập lại cùng thiết bị mở đúng dữ liệu đã lưu.
- Profile và lịch nhắc lưu trên backend bền vững. Xe, geometry và chi phí **chưa đồng bộ giữa thiết bị**. Đăng nhập trên thiết bị khác không tự tải những dữ liệu cục bộ này. Không trình bày đó là đồng bộ đầy đủ.
- Trường hợp mất mạng dùng profile/cache đã lưu; đồng bộ lịch có trạng thái lỗi rõ ràng. Đăng ký và hoàn tất thiết lập yêu cầu backend hoạt động.
- Thông báo khi app đóng vẫn cần FCM/APNs và kiểm thử thiết bị như tài liệu Smart Departure; thêm tài khoản không tự kích hoạt push.

## API

Tất cả endpoint cần `X-App-Token`. Các endpoint cá nhân còn cần `X-Schedule-Token` của tài khoản:

- POST `/api/v1/accounts/register`: username/password → user_id, username, profile, token.
- POST `/api/v1/accounts/login`: tương tự, tạo session mới.
- GET `/api/v1/accounts/me`: profile hiện tại, không trả mật khẩu/hash.
- POST `/api/v1/accounts/setup`: profile + ScheduleInput nhất quán → lưu schedule và đánh dấu hoàn tất trong cùng transaction. Khi đã hoàn tất, gửi lại không sửa lịch hay tạo bản sao; chỉnh lịch qua API departure hiện có.
- POST `/api/v1/accounts/logout`: thu hồi session đang dùng; session thiết bị khác không bị thu hồi.

## Chạy Windows

Trong backend:

```powershell
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Worker chạy riêng như docs/SMART_DEPARTURE.md. Không chạy thêm bản sao worker đang hoạt động.

Trong mobile:

```powershell
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=BASE_MAP_SOURCE=geoapify
```

Tài khoản mới: đi đủ5bước, kiểm tra tuyến đã chọn trong Hành trình, lịch trong Lịch nhắc; mở lại app xác nhận không bị bắt setup lại. Tạo tài khoản khác kiểm tra không thấy xe/chi phí của tài khoản đầu; đăng xuất kiểm tra dữ liệu khách vẫn còn. Không tạo dữ liệu test vào hồ sơ thật.

## Kiểm thử

- Backend `tests/test_accounts.py`: hash/salt, username không phân biệt hoa, login sai, revocation theo session, quyền sở hữu, setup idempotent, validation không lộ password, giới hạn auth, migration giữ dữ liệu khách.
- Flutter `test/personal_setup_test.dart`: namespace/khôi phục, lỗi mạng/setup retry, thông tin bắt buộc, bản nháp, giữ geometry, tạo hành trình gắn đúng lịch. Fake HTTP/temp preferences, không gọi provider thật.
- Regression chạy cả bộ backend/Flutter và Web build. Không kiểm thử đăng nhập/nhận push trên thiết bị thật trong thay đổi này.
