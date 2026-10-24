# TrafficGo — UI và chuyển động

## Baseline và phạm vi

Flutter 3.47.7 / Dart 3.13.5 giữ nguyên, không đổi Codemagic. Baseline: analyze sạch, 128 test Flutter đạt; render 26 trường hợp và 28 ảnh sáng/tối trước khi sửa. Các thay đổi ngoại lệ lịch/thông báo đang chưa commit được giữ lại trên cùng nhánh; không sửa backend/provider/quyền GPS/database trong đợt UI này.

## Thiết kế và hành vi đã triển khai

- Xanh ngọc #007C78; nền xám xanh nhẹ, surface trắng/dark xanh than, accent xanh lam và vàng cam có tương phản. Body 16px, mô tả phụ 14px; tiêu đề/ETA/tổng chi lớn hơn. Khoảng cách 4/8, card 24px, nút tối thiểu 52px.
- Button chung giữ Forui: nhấn scale 0.975, easing easeOutCubic 140ms, bóng nhẹ; khóa hành động đồng bộ ngay khi gọi, đợi đúng Future. Spinner và icon phản hồi ở lớp positioned nên không thay kích thước label. Lỗi không báo thành công; success opt-in hoặc thông báo sau khi lưu thật. Haptic selectionClick chỉ trên Android/iOS hỗ trợ, không chặn tác vụ.
- Forui tap-delay vẫn để zero vì FTappable dùng Future.delayed không hủy được. Chuyển động do TrafficPress quản lý để không giữ timer khi đóng form.
- TrafficEntrance dùng Flutter Animate fade/slide ngắn 280ms, chạy một lần theo State/key. Không bọc bản đồ, không phát lại do ETA/GPS/countdown. TickerMode dừng frame ở tab ẩn; countdown không rebuild khi tab ẩn.
- Map: bộ chọn phương tiện trượt, shortcut địa điểm thật có icon theo nhãn đã lưu, định vị có loading/disabled, route đang chọn có nền/viền/check rõ. Header sheet có ETA và lối tắt tìm tuyến/bắt đầu; không thay camera, routing, attribution hay logic xác nhận đổi tuyến.
- Hành trình: thẻ chuyến tiếp theo làm nổi bật điểm đến và giờ xuất phát, ETA/giờ đến bên dưới, trạng thái đồng bộ mở rộng. Thẻ hành trình mới fade/slide theo ID, không tạo dữ liệu mẫu.
- Garage: header xe, icon và odo dễ thấy; giới hạn nhắc được thu vào mở rộng. Mốc và nguồn tài liệu giữ nguyên.
- Chi phí: ba tổng tiền có icon/accent; chọn biểu đồ 7/30 ngày từ khoản chi thật. Cache widget chart khi dữ liệu/theme/viewport không đổi để tránh chạy lại tween vì rebuild không liên quan; vẫn có bản số liệu chữ.
- Cá nhân: avatar theo nickname và nhóm điều hướng trong card. Dropdown giao diện đặt dưới nhãn để không tràn ở 320px/chữ 200%. Empty states minh họa bằng hình khối và icon Flutter tự dựng, không dùng asset mạng.
- Giảm chuyển động: scale/entrance/toggle/navigation indicator/modal Wolt về trạng thái tĩnh hoặc thời lượng zero; loading button dùng hourglass tĩnh nhưng giữ semantics. Bộ chọn dùng Material SegmentedButton khi chữ lớn; giữ nhãn, selected semantics và điều khiển phím mũi tên.

## Thư viện và nguồn tham khảo

| Nguồn | Vai trò thực tế |
|---|---|
| [Flutter Animate](https://pub.dev/packages/flutter_animate) 4.5.2, BSD-3-Clause | Fade/slide có controller riêng, không loop |
| [Animated Toggle Switch](https://pub.dev/packages/animated_toggle_switch) 0.8.7, BSD-3-Clause | Chọn phương tiện, khoảng thống kê; có fallback chữ lớn và keyboard |
| [Flutter Animated Button](https://github.com/NikhilVadoliya/FlutterAnimatedButton), MIT | Tham khảo feedback, không cài/copy mã; dùng Forui + Flutter |
| [Rive Flutter](https://github.com/rive-app/rive-flutter), runtime MIT | Đã đánh giá; không thêm runtime/asset vì chưa chọn asset có giấy phép phù hợp; minh họa code-native |
| [Wonderous](https://flutter.gskinner.com/wonderous/) | Tham khảo phân cấp và chuyển động ngắn; không sao chép thiết kế/asset |

Transitive mới: flutter_shaders 0.1.5 (BSD-3-Clause) từ Flutter Animate; không dùng shader effect trong app. Forui 0.27.6 vẫn là button/card/theme; Shadcn 0.57.3 chỉ calendar; Wolt 0.11.0 cho modal; FL Chart 1.3.0 thống kê. Các giấy phép được lưu trong docs/licenses.

## Kiểm tra và artifact

`test/motion_ui_test.dart`: Future loading, kích thước, chống bấm lặp touch/keyboard, success sau Future, lỗi/retry, press scale, reduced motion, entrance không replay, toggle keyboard, biểu đồ đúng tiền và cache, modal zero-duration.

Các test hiện có tiếp tục kiểm tra camera/tab identity, giữ tuyến và geometry, xác nhận đổi tuyến, tài khoản/offline, lịch nhắc, chi phí và garage. Các bài UI cũ được điều chỉnh cuộn đến điều khiển trước khi bấm, và mở phần chi tiết vừa được thu gọn; không bỏ assertion nghiệp vụ.

Ảnh và log: build/reports/motion-refresh/. Ảnh trước/sau có cùng kích thước/fixture. Các cặp settings, garage, chi phí và route planner dùng dữ liệu tĩnh tương ứng; ảnh hành trình/lịch có đồng hồ runtime nên giờ tuyệt đối khác nhau, không dùng để so sánh hiệu năng hay dữ liệu giờ.

GIF button-states-widget-render.gif là chuỗi frame từ widget test, thể hiện các trạng thái nhấn/loading/success/error của vài nút; không phải video quay trên thiết bị, không đo tốc độ hay chứng minh 60 fps. Không có browser/thiết bị được điều khiển để xác minh tương tác thật hoặc video màn hình.

Chưa xác minh độ mượt/haptic/keyboard hệ điều hành trên iPhone hoặc Android thật; không khẳng định FPS. Không đổi credentials hoặc dữ liệu người dùng. APK cũ chưa có UI này.
