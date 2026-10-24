# TrafficGo — UI/UX thống nhất

Nhánh: `feature/unified-ui`, từ `a580dad`. Không deploy, không push trong lượt này.

## Baseline và phạm vi thực tế

Đọc README, pubspec, theme/router trong `app/app.dart`, các màn hình Flutter và
bộ test. Không có AGENTS.md trong repository. Stack giữ nguyên: Flutter 3.47.7,
Material 3, Riverpod 3, go_router 16, flutter_map 8, FastAPI. Baseline Flutter:
106 tests đạt. Các luồng đã có được giữ lại, không tạo một app khác:

- Tìm địa điểm bằng tên, GPS foreground, chọn phương tiện, chọn tuyến; camera
  và snapshot geometry của tuyến đã lưu.
- Đề xuất tuyến mới và xác nhận trước khi chuyển, cooldown/ngưỡng ETA hiện có.
- Hành trình hai chiều độc lập; lịch nhắc, lịch sử thông báo, hoàn thành chuyến.
- Khoản chi thật, thống kê; hồ sơ xe, công-tơ-mét, nguồn mốc bảo dưỡng.
- Tài khoản, namespace dữ liệu cá nhân và thiết lập ban đầu bắt buộc.

Các provider và cấu hình local không đổi trong lượt UI. TomTom Routing hiện có
thể được chọn bằng cấu hình, xe máy beta; lớp traffic tile chưa bật. Valhalla vẫn
được ghi rõ là chưa có traffic trực tiếp. Không thêm số liệu hay lịch sử GPS.
Push khi app đóng vẫn cần Firebase/APNs và thiết bị thật.

## Vai trò của 5 nguồn

| Nguồn | Phiên bản/giấy phép | Sử dụng thực tế |
|---|---|---|
| [Forui](https://github.com/duobaseio/forui) | 0.27.6, MIT; font kèm OFL | Nền token/theme, primary button dùng chung cho mọi tính năng, thẻ ETA/chuyến tiếp theo/chi phí/trạng thái trống |
| [Flutter Shadcn UI](https://github.com/nank1ro/flutter-shadcn-ui) | shadcn_ui 0.57.3, MIT | Chỉ calendar ngày một lần, ngày khoản chi và ngày bảo dưỡng; nhãn thứ/tháng tiếng Việt, cùng màu primary |
| [Wolt Modal Sheet](https://github.com/woltapp/wolt_modal_sheet) | 0.11.0, MIT | Lưu/sửa tên, lưu/sửa địa điểm, tạo/sửa lịch từ danh sách, ghi khoản chi, chọn ngày và xác nhận đổi tuyến |
| [Trufi Core](https://github.com/trufi-association/trufi-core) | GPL-3.0, không thêm dependency | Tham khảo UX điểm đi/đến, đổi chiều, địa điểm đã lưu, quan hệ bản đồ và sheet; không sao chép source/tài nguyên và không thay routing |
| [FL Chart](https://github.com/imaNNeo/fl_chart) | 1.3.0, MIT | Bar chart 7 ngày từ JourneyStore, tooltip tiền thật, bản chữ tương đương cho người dùng đọc màn hình |

Đã xem source package thực tế trong Pub cache và kiểm tra SDK/LICENSE của 4
dependency; Trufi đã xem README/LICENSE và
`packages/trufi_core_search_locations/lib/src/models/search_location_bar_configuration.dart`.
Các bản giấy phép dependency được giữ tại `docs/licenses/`. Flutter tự thu thập
licence của các package khi build. Không tải tài nguyên hoặc mã GPL vào app.

Forui 0.27.6 yêu cầu Flutter >=3.47 và Dart >=3.13; phù hợp toolchain/CI hiện có.
Shadcn yêu cầu Flutter >=3.41, Dart >=3.11; Wolt và FL Chart đều giải dependency
thành công. Khai báo SDK tối thiểu được cập nhật cho đúng yêu cầu thực tế,
`pubspec.lock` được giữ. Không nâng Flutter hay sửa workflow Codemagic.

Forui mới dùng `material_ui` riêng. Không sử dụng hàm chuyển theme trả về kiểu
ThemeData khác Flutter Material. Thay vào đó Material forms cũ nhận chung token
màu, font Roboto, kích thước vùng chạm, khoảng cách và bo góc. Primary actions
được chuyển về một wrapper Forui duy nhất; Shadcn không tạo kiểu button/input
thứ hai trong các form thông thường. ThemeData được cache để tránh dựng lại
hàng loạt style mỗi frame.

## Các thay đổi giao diện

- Home sau onboarding có 4 tab: Bản đồ / Hành trình / Xe của tôi / Cá nhân.
  Tab được mount khi cần và giữ bằng IndexedStack; chuyển tab không huỷ camera
  hay tuyến đang chọn. Back từ tab khác trở về Bản đồ. Router và đường dẫn từ
  thông báo vẫn giữ nguyên; các trang con vẫn dùng Navigator/go_router cũ.
- Bản đồ: persistent draggable sheet, snap/expand tới 85%; nút chọn địa điểm
  đã lưu thật, khu vực tìm kiếm có thể cuộn khi chữ lớn. Tuyến phụ màu xám,
  tuyến chính xanh dương; selected state có icon/text, không chỉ dựa vào màu.
  Thẻ ETA có giờ đến ước tính khi xuất phát bây giờ, khoảng cách, nhãn nhanh
  nhất và ghi chú nguồn ETA. Chuyến tiếp theo chỉ xuất hiện khi có lịch.
  Attribution hiện có giữ ở phần bản đồ và đường dẫn bản quyền trong sheet.
- Hành trình: phân cấp tiêu đề, card hành trình, truy cập lịch/chi phí trực tiếp,
  giữ hai tab Chiều đi/Chiều về và mọi handler lưu snapshot.
- Lịch nhắc: thẻ chuyến tiếp theo, nhãn đồng bộ thực tế, form Wolt từ danh sách;
  `/schedule-edit` vẫn mở trang đầy đủ cho deep link. Ngày chọn bằng calendar
  dùng chung, giờ vẫn dùng picker Material đã bản địa hoá để giữ khả năng nhập.
- Xe: phân cấp nội dung, card/empty state, mốc người dùng/hãng giữ nguồn cũ,
  ngày bảo dưỡng theo calendar chung. Không tự tạo chu kỳ hoặc cộng km.
- Chi phí: thẻ hôm nay/tuần/tháng, định dạng VNĐ có dấu phân nhóm, FL Chart và
  bản chữ; form khoản chi nằm trong modal với validation và save handler cũ.
- Cá nhân: địa điểm đã lưu dễ tìm; thông số backend/token/metrics được gom vào
  mục mở rộng Kết nối và chẩn đoán. Quyền và trạng thái tính năng vẫn trung thực.
- Tài khoản/onboarding: primary action và theme chung, từng bước có tiêu đề/icon,
  giữ kiểm tra bắt buộc, bản nháp và chống gửi lặp.

Không đổi storage, provider, API key hay dữ liệu người dùng. Không biến mọi form
thành modal: màn chỉnh tuyến, hành trình hai chiều và thiết lập nhiều bước vẫn
giữ trang đầy đủ. Persistent sheet trên map không có barrier chặn thao tác map.

## Kiểm chứng và giới hạn

- Test mới: tiền VNĐ; chuyển tab giữ cùng instance map; chọn route; xác nhận/từ
  chối đổi route không ghi đè bản lưu; modal khoản chi với keyboard inset;
  calendar chỉ trả kết quả khi xác nhận.
- Matrix 13 màn hình × 2 cấu hình: 390×844 light và 320×694 dark với chữ 200%;
  kiểm tra initial/scroll và xuất PNG. Chart có thêm ảnh khi cuộn.
- Test thống kê kiểm tra trực tiếp 7 cột và tổng giá trị, không bám vào 7 thanh
  LinearProgressIndicator cũ. Test thao tác cuộn tới widget đã lazy-build thay
  vì giả định mọi nút luôn có trong cây.
- Sửa phát hiện: Forui button không wrap nhãn dài; Material ink trong card;
  font tiêu đề trong renderer test; timer phản hồi button trong test; vùng cuộn
  sau khi thêm header; nhãn ETA xe máy trước đây mặc định nói không có traffic.

Lệnh chạy từ `mobile/` trên Windows:

```
flutter pub get
flutter analyze
flutter test
flutter build web --output build/web-ui-refresh
```

Xuất ảnh QA (không bắt buộc khi test CI):

```
flutter test test/full_ui_matrix_test.dart --dart-define=CAPTURE_UI=true --dart-define=QA_FONT_PATH=C:/path/to/roboto-regular.ttf
```

Ảnh kiểm thử dùng fixture tách biệt, không phải screenshot dữ liệu cá nhân hoặc
bằng chứng traffic trực tiếp. Không được đưa fixture này vào production.
PNG được render bởi Flutter test; chưa kiểm tra browser tương tác/iPhone thật,
VoiceOver/TalkBack thực tế, bàn phím hệ điều hành hay Xcode build. Không tuyên bố
push khi app đóng, background GPS hoặc traffic tile đã được kiểm thử.

Kết quả cuối và vị trí ảnh/bundle được ghi tiếp trong PROGRESS.md sau khi build.


## Kết quả cuối

- `flutter analyze`: No issues found.
- `flutter test`: 113/113 đạt (baseline 106); matrix capture 26/26 đạt.
- `pytest`: 91/91 đạt, 3 cảnh báo deprecation từ dependency hiện có.
- `flutter build web`: thành công, 177 giây trong lần build này.
- 28 PNG QA tại `build/reports/ui-refresh/`; bundle báo cáo `build/reports/TrafficGo-UI-refresh.zip`.
- Preview local 5173 phục vụ đúng SHA-256 của bundle mới đã build; chưa có kiểm thử browser tương tác.
- JS release: 4.612.920 byte so với 4.159.140 byte trước đó (tăng khoảng 11%).
  Không suy ra latency/p50/p95 từ kích thước; cần đo trên thiết bị thật.
- Quét secret theo các giá trị cấu hình local: source thay đổi và web JS đều đạt.
- Codemagic không thay đổi; không có kiểm thử Xcode/iOS, signing hoặc push thật.
