# Build iOS trên Codemagic

1. Add application, kết nối GitHub và chọn buiduytung2204-svg/trafficgo-ios.
2. Dùng codemagic.yaml ở root; chọn branch main.
3. Tạo environment group **trafficgo_build**; cho app dùng nhóm này.
4. Thêm **API_BASE_URL** vào group. Không đưa provider keys hoặc token tài khoản vào Flutter build.
5. Chạy thủ công workflow phù hợp. Kiểm tra quota macOS miễn phí trước khi chạy; không có auto-trigger/publish.

## Backend Windows và build chưa ký
Chọn **ios-unsigned**. API_BASE_URL có thể là http://192.168.1.50:8000 (thay IPv4 thật lấy từ ipconfig). Đặt **IOS_ALLOW_LOCAL_HTTP=1** trong group nếu dùng HTTP LAN. Với HTTPS thì không cần biến này.

Khi chạy app, iPhone cùng Wi-Fi với Windows; backend nghe --host 0.0.0.0 --port 8000 và Firewall cho phép mạng riêng. localhost trên iPhone không phải máy tính. CI không cần gọi backend LAN để compile.

Script chỉ cho HTTP ở IPv4 riêng khi bật rõ tùy chọn, thêm quyền mạng LAN và ATS exception vào checkout unsigned trên CI. Info.plist production trong Git không đổi. Đây là cấu hình thử nghiệm.

Workflow chạy preflight, pub get theo lockfile, analyze, tests, pod install và flutter build ipa --no-codesign. Flutter tạo archive, bỏ export signed IPA. Artifact:
- TrafficGo-unsigned.app.zip: device app bundle.
- TrafficGo-unsigned.xcarchive.zip: archive có metadata.
- TrafficGo-UNSIGNED-resign-input.ipa: Payload/Runner.app để ký lại bằng công cụ phù hợp; KHÔNG cài trực tiếp.
- README và build-config.json ghi kiểu build.

## IPA đã ký
Chọn **ios-signed** sau khi upload certificate và profile Ad Hoc vào Codemagic Code signing identities. Bundle ID **vn.trafficgo.trafficgo**; Team/certificate/profile khớp; UDID iPhone có trong profile. API_BASE_URL phải HTTPS.

Workflow cài pods, áp dụng profile bằng xcode-project use-profiles, tạo export options và build IPA. Artifact gồm IPA và archive ZIP. Không tự upload TestFlight/App Store. TestFlight cần app_store profile/distribution type phù hợp.

## Cấu hình
Flutter 3.47.7, CocoaPods, tắt Swift Package Manager, Xcode latest, iOS 15.0+. Build number từ PROJECT_BUILD_NUMBER. Tên TrafficGo và icon đã có trong project. Chưa pin Xcode trước khi có build macOS thành công.

Backend .env, keys và database vẫn ở Windows, không đưa vào CI. Dữ liệu browser local không tự chuyển sang iPhone. Không gửi mật khẩu hoặc signing secrets trong chat.

## Kiểm chứng và giới hạn
Chạy trên Windows: python scripts/check_ios_config.py và python scripts/test_ios_build_config.py. Trong mobile: flutter pub get --enforce-lockfile, flutter analyze, flutter test.
Phiên Windows chưa chạy Xcode/macOS CI và chưa có artifact mới, chưa xác minh ký/cài trên iPhone.

Nguồn: [Flutter YAML](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/), [iOS signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/), [ký/cài IPA](IPA_SIGNING.md).
