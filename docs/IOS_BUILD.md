# Build iOS từ Windows

Không cài Xcode trên Windows. Commit project vào repository của bạn rồi tự kết nối Codemagic khi muốn chạy; phiên này không push/deploy hoặc gọi CI trả phí. Xem [Codemagic Flutter builds](https://docs.codemagic.io/flutter-configuration/flutter-projects/) và [YAML signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/).

codemagic.yaml có hai workflow không auto publish:

1. ios-unsigned: pub get → analyze → test → pod install → flutter build ios --no-codesign → zip Runner.app → xcodebuild archive với CODE_SIGNING_ALLOWED=NO. .app.zip là device bundle để kiểm tra hoặc chuẩn bị ký lại, không phải IPA đã ký. .xcarchive là archive có metadata, không tự cài được.
2. ios-signed: chỉ dùng sau khi upload certificate/profile đúng Team/Bundle trong Codemagic. ad_hoc mặc định, bundle vn.trafficgo.trafficgo. use-profiles tạo export_options.plist, flutter build ipa tạo archive và export IPA. TestFlight cần đổi distribution_type thành app_store và profile phù hợp; tự upload sau kiểm thử.

Đổi API_BASE_URL từ example.invalid sang backend HTTPS. Không đưa TomTom key vào dart-define. Flutter được pin 3.47.7; Xcode latest nên pin khi đã có build thành công. Workflow tắt Swift Package Manager và dùng CocoaPods nhất quán. Deployment target iOS 15.0, app TrafficGo; bundle vn.trafficgo.trafficgo cần đăng ký hoặc thay bằng ID của bạn ở project và YAML. Icon hình học riêng đã có ở mobile/assets/trafficgo-icon.png và các asset catalog; có thể tái tạo bằng scripts/generate_icons.py (Pillow).

Signing export khác compile. Không có certificate/profile/CI access trong phiên; chưa có IPA hoặc kết quả iOS compile. Không thể cam kết unsigned archive sẽ export được signed IPA bằng mọi công cụ. Kiểm tra plugin location, secure storage và notification trên macOS/iPhone. Notification MVP chưa xin quyền/chưa bật thông báo; không yêu cầu background location.

Sau khi CI chạy: tải build log, .app.zip/.xcarchive hoặc .ipa; lưu kết quả test, Flutter/Xcode version. Kiểm tra Info.plist, privacy manifest của dependencies và App Store privacy trước upload. Không thêm NSAllowsArbitraryLoads production.
