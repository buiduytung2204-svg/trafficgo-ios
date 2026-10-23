# Ký và cài

Phân biệt: compile unsigned .app → archive .xcarchive → export .ipa → IPA ký đúng profile → cài trên thiết bị hợp lệ. Đuôi .ipa không chứng minh đã ký hoặc có thể cài.

## A. Apple ID miễn phí

[Apple account overview](https://developer.apple.com/help/account/basics/about-your-developer-account) ghi Personal Team provisioning profile hết hạn 7 ngày. Không có TestFlight/App Store distribution với tài khoản miễn phí. CI unsigned không cần Apple account nhưng CI có thể có quota/phí riêng. Không tự chạy nếu vượt free allowance.

Tải unsigned Runner.app.zip từ macOS workflow, giải nén vào Payload/Runner.app và ZIP thư mục Payload rồi đổi đuôi .ipa để tạo **gói đầu vào ký lại**; đây không phải export IPA có chữ ký hợp lệ. Ví dụ trên macOS: mkdir Payload; ditto Runner.app Payload/Runner.app; zip -r TrafficGo-resign-input.ipa Payload. Công cụ ký lại có thể không chấp nhận một số bundle/entitlement; cần kiểm tra kết quả thực tế.

[Sideloadly chính thức](https://sideloadly.io/) và [FAQ](https://sideloadly.io/faq): cài bản Windows cùng iTunes/iCloud web theo hướng dẫn của họ; kết nối iPhone, Trust computer, chọn IPA đầu vào, nhập Apple ID **trong công cụ**, ký/cài. Bật Developer Mode nếu iOS yêu cầu, tin cậy profile theo thiết bị. Tài khoản miễn phí thường phải ký lại trong 7 ngày và có giới hạn app/device/capability. Không cung cấp mật khẩu Apple ID trong chat. Chưa thử ký lại artifact của project này.

## B. Apple Developer

Đăng ký bundle ID, certificate và profile với Apple Developer của bạn. Ad Hoc yêu cầu UDID thiết bị nằm trong profile. Upload .p12 và provisioning profile vào kho signing của Codemagic, giữ password dưới dạng encrypted secret. Team ID, certificate, bundle ID và kiểu distribution phải khớp. Chạy ios-signed; cài bằng phương thức Ad Hoc hợp lệ sau khi kiểm tra code signature. TestFlight: app_store profile, App Store Connect app record và upload IPA được xác thực; không tự phát hành từ workflow này.

## C. Certificate riêng

Import .p12 có private key cùng .mobileprovision trong Codemagic signing settings. Xác minh hạn dùng, TeamIdentifier, application-identifier, entitlements, danh sách device và loại profile. Dùng export method phù hợp; không mặc định certificate bất kỳ ký được mọi bundle hoặc thiết bị. Không commit .p12/.mobileprovision, không gửi vào chat. Nếu thất bại, đọc build/export log đã che bí mật. Chỉ xác nhận cài thành công sau khi mở app thật trên iPhone.
