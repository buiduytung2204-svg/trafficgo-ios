# QA14 — Người mới dùng TrafficGo trong 14 ngày mô phỏng

Đây là kịch bản thời gian tăng tốc, không phải hai tuần lái xe/GPS thật. Không
biến chuyến mô phỏng thành bằng chứng quãng đường hay traffic lịch sử. Source
app và provider không đổi trong lượt QA này.

## Tài khoản và cách mở dữ liệu

Tài khoản mới được tạo bằng API register/login/setup trên backend Windows.
Thông tin đăng nhập chỉ nằm trong file bị Git ignore:
`build/reports/qa14/account.private.json`. Không đưa file này lên Git.

1. Mở `http://localhost:5173`, vào **Cá nhân → Tạo tài khoản / đăng nhập → Đã có
   tài khoản? Đăng nhập**. Dùng tài khoản QA được bàn giao. Giữ nguyên app access
   token backend đã cấu hình.
2. Đóng các tab TrafficGo khác. Mở `http://localhost:5173/qa14.html` trong **cùng
   trình duyệt và đúng origin localhost:5173**, nhấn **Nạp dữ liệu mô phỏng**.
3. Mở lại TrafficGo. Kiểm tra Hành trình, Chi phí, Xe của tôi và Lịch nhắc/Thông báo.

Trang nạp kiểm tra user_id đang đăng nhập, không ghi đè tài khoản khác, dừng nếu
đã có dữ liệu và không nạp lại sau khi đã nhập thành công. Không sửa access token
hay session. Dữ liệu trình duyệt lưu theo namespace tài khoản; không xóa storage
toàn trình duyệt. Giữ các thay đổi bạn thử sau khi đã nạp.

Lịch và notification inbox nằm trong DB backend; xe/tuyến/chi phí vẫn là local
preferences. Đăng nhập trên điện thoại khác **không tự đồng bộ** phần dữ liệu
local này. Trang nạp hiện dành cho web local, không phải tính năng sync production.
Nếu build lại web, copy `backend/scripts/qa14_import.html` và fixture dataset vào
thư mục đang serve trước khi dùng trang nạp.

## Dữ liệu chuẩn

- Nhà: NHS Trung Văn; Trường: Đại học CMC cơ sở 2. Search Geoapify thật.
- Hai chiều được tính riêng bằng routing API hiện tại, chọn một alternative thật
  nếu provider có. Geometry và retrieved_at là snapshot thời điểm tạo fixture.
  Không tự đảo polyline và không gọi routing lặp cho 14 ngày.
- 1 hành trình, xe máy Wave Alpha 2024, 2 lịch T2–T6: đến trường 07:30 và đến nhà
  18:30. Chuẩn bị 15 phút, dự phòng 10 phút.
- 10 ngày trong tuần × 2 chiều = 20 lượt dự kiến; 1 bỏ qua + 1 hủy = 18 lượt hoàn thành.
- 14 khoản mua xăng × 50.000; 10 khoản gửi xe × 10.000; 2 khoản bảo dưỡng × 100.000
  = **26 khoản / 1.000.000 VNĐ**. Đây là thao tác nhập chi phí giả lập, không tính
  từ GPS/tiêu hao. Ngày không có chuyến hoàn thành vẫn có thể có khoản mua xăng,
  gửi xe được nhập riêng; không suy ra chuyến đã đi từ khoản chi.
- 2 bản ghi bảo dưỡng giả lập liên kết cùng ID khoản chi, không tạo chi phí trùng.
  Mốc nhắc do người dùng tự đặt để thử, không phải khuyến cáo Honda.
- 40 notification events có nhãn **QA MÔ PHỎNG** trong inbox. Không phải 40 push
  thật. Để lại một sự kiện chưa đọc để kiểm tra UI.

Thời gian chuẩn bị/xuất phát trong lịch sử dùng ETA mock 15/25/40/60 phút,
`eta_source=SIMULATION_QA_ONLY`, `traffic_aware=false`. Những giá trị này không
phải traffic thật. Snapshot tuyến thật và ETA mock lịch sử là hai lớp riêng.

## Test cases

| Case | Thao tác/điều kiện | Kết quả cần thấy | Cách đã kiểm tra |
|---|---|---|---|
| 01 | Tạo account mới | Profile chưa setup; dữ liệu người khác không đổi | API thật |
| 02 | Sai mật khẩu rồi đăng nhập đúng | 401 khi sai; đúng identity khi hợp lệ | API thật |
| 03 | Setup thiếu tên/xe/địa điểm, quay lại bước trước | Không bỏ qua validation; giữ bản nháp | Widget tests hiện có |
| 04 | Chọn Nhà/Trường từ tìm kiếm | Kết quả và tọa độ có provider | Geoapify thật |
| 05 | Tìm đi và về riêng | Hai snapshot riêng; mở lại không tự tính tuyến khác | API thật + store/widget tests |
| 06 | Chọn/giữ tuyến đề xuất | Chỉ chuyển sau xác nhận; không ghi đè bản lưu | Widget tests mock provider |
| 07 | Tạo/sửa/tắt/xóa lịch thử | API lưu đúng; còn đúng 2 lịch chính | API thật |
| 08 | Gửi setup hai lần | Không tạo lịch/hành trình trùng | API + widget tests |
| 09 | ETA 15/25/40/60, cần đến07:30 | Chuẩn bị06:50/06:40/06:25/06:05; xuất phát07:05/06:55/06:40/06:20 | Engine với clock mock |
| 10 | ETA25 tăng40 | Xuất phát sớm hơn15phút; không mô tả mock là realtime | Engine |
| 11 | Đến giờ/đi muộn; tick lặp | Đúng loại event, không nhân đôi | Engine + backend tests; inbox QA seeded riêng |
| 12 | Bỏ qua/hủy một lượt | Không tính vào chuyến hoàn thành | Snapshot mô phỏng + store/backend tests |
| 13 | Hoàn thành hai lần cùng session | Một completion | Bộ test journey hiện có |
| 14 | Nhập/sửa/xóa khoản chi | Tổng đổi đúng; xóa trả lại tổng ban đầu | Store + form Wolt tests |
| 15 | Tiền âm/0/>1tỷ, 31/02 | Bị từ chối, không làm mất khoản chi cũ | Store/form tests |
| 16 | Xem chi phí và chart | 7 cột khớp từng ngày, không tạo thêm chuyến | FL Chart tests + đối soát CSV/JSON |
| 17 | Công-tơ-mét5999→6000→6001, mốc6000 | Sắp đến hạn → Đến hạn → Quá hạn | GarageStore thật trong test |
| 18 | Xác nhận bảo dưỡng hai lần | Thêm một history; không tự tạo chi phí | GarageStore test |
| 19 | Đánh dấu thông báo đã đọc | Persist vào DB, UI có thể mở tuyến liên quan | API read thật; route mở bằng code/test hiện có |
| 20 | Logout, đổi tài khoản, mở lại | Không thấy dữ liệu namespace tài khoản khác | Store/widget tests |
| 21 | Chuyển4tab, chữ200%, dark, bàn phím | Map instance giữ nguyên, không tràn layout | Matrix/interactions tests |
| 22 | Mất mạng/API429/timeout | Hiển thị lỗi, không báo đồng bộ giả, không retry vô hạn | Mock automated tests |
| 23 | Backend/DB mở lại | Persistence và idempotency giữ nguyên | Tests reopen; không restart dịch vụ người dùng để giả lập14ngày |
| 24 | Xin GPS, lái xe thực, khóa màn hình | Cần đối chiếu trên thiết bị thật | **Chưa thực hiện trong lượt QA này** |
| 25 | Push khi app đóng | Chỉ nghiệm thu sau Firebase/APNs và thiết bị | **Chưa cấu hình/không tuyên bố hoạt động** |

## Chạy lại

Tạo fixture local mới (tạo account mới, tiêu thụ 2 routing requests, không chạy
liên tục và không đưa vào CI):

```
cd backend
.venv\Scripts\python scripts/create_qa14.py
```

Test store với chính dataset đã tạo:

```
cd mobile
flutter test test/qa14_acceptance_test.dart --dart-define=QA_DATASET_PATH=C:/absolute/path/to/build/reports/qa14/dataset.json
```

Không cung cấp QA_DATASET_PATH thì test dùng fixture độc lập, không gọi API thật,
không đọc DB cá nhân. Full suite: `flutter test`; backend: `python -m pytest -q`.

Kết quả, ledger theo ngày, dataset và hướng dẫn account cụ thể nằm trong
`build/reports/qa14/`. Không đóng gói password/session vào báo cáo công khai.
