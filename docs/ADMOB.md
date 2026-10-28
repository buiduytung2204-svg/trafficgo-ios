# AdMob thử nghiệm

Chỉ dùng Google sample App ID và ad unit ID trên Android/iOS. Không tải quảng cáo
thật, không tạo doanh thu, không cần cung cấp mật khẩu AdMob. Web/desktop bỏ qua SDK.
Dependency chính thức: google_mobile_ads 9.2.0 (Apache-2.0), tương thích Flutter đang dùng.

Banner adaptive nằm trong shell bốn tab chính, có nhãn thử nghiệm và khoảng phân
cách với thanh tab. Các màn được push độc lập ngoài shell chưa có banner riêng.
Ẩn khi bàn phím mở hoặc đang dẫn đường. Không dùng quảng cáo trên Web giả làm AdMob.

Interstitial chỉ áp dụng khi đổi tab chính, không phải nút Back, form, modal hay
deep link thông báo. Không hiện trong ba phút đầu; sau mỗi lần hiện thành công
phải chờ ít nhất ba phút. Nếu chưa sẵn sàng/lỗi thì chuyển ngay; khi đã hiện thì
đóng quảng cáo mới chuyển, chặn thao tác chuyển tab trùng. Bộ đếm trong process.
Không có quảng cáo khi đang điều hướng.

UMP kiểm tra quyền yêu cầu quảng cáo trước khởi tạo SDK. Chưa phát hành quảng cáo
thật: trước đó phải cấu hình Privacy & messaging, quyền riêng tư, privacy options
và cấu hình iOS theo yêu cầu hiện hành; không tự bật ATT hay gửi tọa độ GPS vào ad request.

## Kiểm tra thiết bị

Build APK hoặc iOS mới; bản đã cài không tự nhận SDK. Cho phép UMP hoàn tất nếu
có form. Kiểm tra banner test ở bốn tab, đổi tab trước/sau ba phút, đóng interstitial,
thử offline, xoay màn hình, mở bàn phím và bắt đầu/kết thúc dẫn đường. Xác minh map
không reset và nút GPS/attribution không bị che. Test unit/widget không chứng minh
Google đã phân phối quảng cáo trên điện thoại thật.

## Kết quả kiểm tra local

- `flutter pub get`: thành công; thêm SDK và bốn dependency WebView phụ thuộc,
  không nâng cấp dependency sẵn có.
- `flutter analyze`: không có issue.
- `flutter test`: 220 đạt, 1 preview bỏ qua. Sửa assertion thống kê cũ phụ thuộc
  ngày: cùng số tiền có thể xuất hiện ở cả tổng kỳ và nhóm chi phí.
- Build Web release thành công; bản local tại http://localhost:5173 được cập nhật.
- Android ARM64 debug build thành công (`flutter build apk --debug --target-platform
  android-arm64 --no-pub`). Đây là kiểm tra biên dịch SDK, dùng backend mặc định
  localhost; không phải APK đã cấu hình tunnel để cài và sử dụng backend trên điện thoại.
- Sau xử lý banner tải lỗi, analyze sạch và 3 test quảng cáo chạy lại đều đạt.
- Chưa kiểm thử phân phối quảng cáo native trên iPhone/Android thật; không có build
  Xcode trên Windows. Không commit/push hoặc sửa dữ liệu tài khoản.

Nguồn: https://developers.google.com/admob/flutter/quick-start,
https://developers.google.com/admob/flutter/test-ads,
https://developers.google.com/admob/flutter/privacy.
