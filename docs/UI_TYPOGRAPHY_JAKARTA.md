# Plus Jakarta Sans — typography local

Nguồn: https://github.com/google/fonts/tree/main/ofl/plusjakartasans — variable version 2.071; static instances tại wght=500/600/700 bằng fontTools. SIL OFL được đóng gói trong mobile/assets/fonts/PlusJakartaSans-OFL.txt. Không thêm package hoặc nâng toolchain.

## Phân cấp
- Nội dung, mô tả phụ: Medium 500.
- Nhãn, navigation tab, tên địa điểm: SemiBold 600.
- Tiêu đề, button, ETA/số liệu: Bold 700. Không sử dụng 800/900 trong mobile/lib.
- Material/primaryTextTheme, Forui, Shadcn calendar, modal và button dùng chung: PlusJakartaSans. Không dùng fallback Be Vietnam Pro cho tiếng Việt. Emoji/icon hệ thống vẫn do platform xử lý.

Giữ layout, spacing, animation và palette. Màu chữ phụ hiện có vượt 4.5:1 trên surface sáng/tối theo unit test nên không đổi màu. Các size typography đã thiết lập được giữ; không phóng to hàng loạt.

## Kiểm chứng
Cmap của ba file local đủ ký tự tiếng Việt NFC/NFD; SHA-256 và coverage: build/reports/jakarta-final/coverage.json. Test jakarta_typography_test.dart render đúng các câu tiếng Việt yêu cầu với font local 500/600/700, so sánh pixel NFC và NFD. Ảnh thực sự là Flutter widget render Windows, không phải screenshot thiết bị iPhone hoặc iOS Simulator.

full_ui_matrix_test.dart kiểm tra 14 màn × 6 tổ hợp: light/dark, 100/150/200%; màn 390px hoặc 320px. Dữ liệu TEST riêng; tile mạng không được tải trong widget test. Ảnh before/after cùng viewport, nhưng giờ lịch fixture thay đổi theo thời điểm chạy test.

Outfit tạm thời được bỏ khỏi pubspec và chuyển asset chưa commit vào build/reports/jakarta-final/outfit-provisional. File Be Vietnam Pro cũ giữ nguyên trên đĩa, không đăng ký làm font UI. Không thay backend/API/database hoặc nghiệp vụ trong đợt typography; giữ nguyên các thay đổi nút Hủy trước đó. Không commit/push/deploy online.

## Kết quả cuối
- flutter pub get: thành công; không nâng dependency.
- flutter analyze: No issues found.
- flutter test --dart-define=CAPTURE_UI=true: 204 passed, 1 manual proof skipped.
- flutter build web: thành công 63.9s. Web local đã cập nhật, URL http://localhost:5173/?build=jakarta-0bfb1b8aba99.
- FontManifest Web chỉ có PlusJakartaSans cho chữ UI; không Outfit/BeVietnamPro. SHA-256 bản JS phục vụ khớp output build. Kiểm tra secrets không phát hiện giá trị cấu hình backend trong JS.

## File typography thay đổi
- mobile/lib/app/app.dart
- mobile/lib/features/departure/screens.dart
- mobile/lib/features/map/home_overview.dart
- mobile/lib/features/map/map_screen.dart
- mobile/lib/features/settings/screens.dart
- mobile/lib/core/design/components.dart
- mobile/lib/core/design/sheets.dart
- mobile/lib/core/design/traffic_theme.dart
- mobile/pubspec.yaml
- mobile/assets/fonts/PlusJakartaSans-{Medium,SemiBold,Bold}.ttf
- mobile/assets/fonts/PlusJakartaSans-OFL.txt
- mobile/test/full_ui_matrix_test.dart
- mobile/test/jakarta_typography_test.dart

Các thay đổi PlacePicker/unified_ui_test và logic Hủy đã có trước lượt typography này, được giữ nguyên. Ảnh: build/reports/jakarta-final/after, vietnamese, home-before-after.png. Không có kiểm chứng iPhone thật/iOS Simulator trong môi trường Windows.
