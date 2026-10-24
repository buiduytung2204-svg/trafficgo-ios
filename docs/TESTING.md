# Kiểm thử TrafficGo hiện tại

## Lệnh chạy trên Windows

Từ backend:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m pip check
```

Từ mobile (hoặc junction C:\Users\tungb\trafficgo-work):

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub --no-wasm-dry-run --dart-define=BASE_MAP_SOURCE=geoapify --dart-define=API_BASE_URL=http://localhost:8000
```

Từ root: `python scripts/check_ios_config.py`. Đây chỉ là kiểm tra plist/XML/project, không phải build hay ký iOS.

Junction trỏ đúng source mobile, không phải bản copy; giúp Flutter/Dart tránh lỗi đường dẫn Unicode trên Windows. Phiên hiện dùng SDK tại C:\Users\tungb\trafficgo-tools\flutter\bin. Không commit các file môi trường, database hay build/report chứa dữ liệu cá nhân.

## Phạm vi tự động

- Backend: validation/auth, ownership, error/timeout/429/Retry-After, normalization/polyline precision, quotas/cache/coalescing, accounts/setup/session, migrations không mất dữ liệu, scheduler/timezone/cross-midnight/ETA/terminal-state/idempotency/device-token contracts.
- Flutter: models, ETA, selection/cooldown, camera/error/cancellation, search debounce/offline, GPS permission/fallback bằng mock, saved routes và geometry, chiều đi/về riêng, expense CRUD/statistics, completed-trip idempotency, lịch nhắc/cache, onboarding/account isolation, maintenance km/date/manual provenance, persistence/corruption.
- `full_audit_regression_test.dart`: pending writes khi provider bị dispose, ngày chi phí hợp lệ, trạng thái online phục hồi, phương tiện mặc định, phạm vi xóa cục bộ, CRUD và giữ lịch sử.
- `full_ui_matrix_test.dart`:13màn hình ×2cấu hình (390px chữ100% sáng;320px chữ200% tối), kiểm tra layout ban đầu và sau cuộn. Các bước onboarding có ma trận và ảnh riêng trong personalization_cases_test.dart.
- Nguồn API trong automated tests được mock rõ ràng; database/prefs kiểm thử riêng. Không biến các fixture thành dữ liệu realtime.
- Kết quả lượt kiểm tra gần nhất, lỗi trước/sau sửa và live smoke nằm trong docs/FULL_FUNCTION_AUDIT.md cùng build/reports/full-audit.

## Smoke test thật có kiểm soát

Stack đang chạy: Geoapify nền/search + Valhalla routing. **Không dùng hoặc bật lại TomTom.** Chỉ gọi số lượng nhỏ request qua backend đã cấu hình, giữ nguyên budget/rate-limit và không bỏ qua429. Kiểm tra kết quả và trạng thái nguồn, không chỉ HTTP200.

Đã có smoke test trong lượt audit:2search (NHS Trung Văn, CMC cơ sở2),2route (car/motorcycle),1tile nền, health và traffic status. Quota có thể tính khác nhau giữa endpoint backend và request upstream; không suy ra số credit từ số backend request.

Traffic realtime hiện unavailable. ETA Valhalla là routing estimate, không xác nhận đã xét ùn tắc. Motorcycle endpoint có thể trả tuyến với profile hiện tại nhưng không phải bằng chứng pháp lý về mọi đường cấm xe máy tại Việt Nam.

## Còn phải kiểm tra trên thiết bị/dịch vụ thật

1. Android/iPhone: hộp quyền, denied/blocked, dịch vụ vị trí tắt, approximate/precise, native fallback và GPS stream ngoài đường. Unit tests chỉ chứng minh nhánh logic với mock.
2. Di chuyển thật: heading, bám tuyến, lệch tuyến nhiều fix, đề xuất tuyến thay thế và xác nhận đổi tuyến, dừng stream khi kết thúc/background. Không thao tác khi đang lái.
3. Browser/device: viewport đầy đủ, font fallback, bàn phím, gestures và local notifications. Ảnh Flutter render không thay thế kiểm thử này.
4. FCM/APNs: credentials, device token thật, nhận push khi app đóng và mở đúng hành trình. Chưa tuyên bố hoàn tất.
5. PostgreSQL thật: chạy migration và kiểm tra constraints/ownership. Bộ test hiện dùng SQLite tạm; không tự deploy database.
6. macOS CI: Xcode compile/archive, signing/provisioning, IPA và cài iPhone. Codemagic có placeholder API_BASE_URL cần cấu hình khi build thật; Windows static check không chứng minh CI đã thành công.

Không thể kết luận ứng dụng không còn lỗi chỉ từ test tự động. Báo cáo cần tách phần đã chạy, giới hạn nguồn dữ liệu và các bước chưa kiểm chứng.
