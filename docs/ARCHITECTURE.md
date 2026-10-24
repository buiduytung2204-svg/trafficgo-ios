# Kiến trúc

Flutter Material 3 + Riverpod (state thiết bị), GoRouter (home/settings/saved), flutter_map (raster và polyline), Dio, geolocator. GPS khi foreground, không background permission. SharedPreferences lưu tùy chọn và địa điểm cục bộ; secure storage lưu access token. Không cần account ở guest mode.

FastAPI → provider abstraction → TomTom HTTPS. Schema chuẩn hóa tọa độ, route, ETA, geometry, legs, instruction, provider, timestamp và vehicle. Tọa độ giới hạn vùng Hà Nội rộng; không hỗ trợ tuyến toàn quốc. Google/HERE là adapter chưa bật có lỗi 501 rõ ràng. /routes/refresh tính lại từ current origin và trả proposal; client không âm thầm đổi tuyến.

PostgreSQL/SQLAlchemy với Alembic: users, saved_places, saved_routes, route_checks, user_settings; FK cascade và owner indexes. Không tự create schema khi server start. Migration 001 dùng DDL độc lập models runtime. route_checks không được ghi mặc định. App guest lưu places và hai điểm tuyến thường dùng cục bộ, không lưu provider geometry. Bảng saved_routes sẵn sàng nhưng chưa có endpoint đồng bộ tuyến; luồng đăng nhập/đồng bộ UI chưa triển khai.

Endpoint cá nhân yêu cầu JWT HS256 exp/sub/iss/aud từ auth service tin cậy và access token ứng dụng. Không có endpoint tự phát JWT. Không bật sync khi chưa có JWT_SECRET. Không đưa service-role key vào client. Triển khai Supabase cần adapter xác minh JWKS thay cho HS256 hiện tại; không dùng trực tiếp token bất kỳ.

Hạn chế: limiter/budget bộ nhớ chỉ một process, không bền vững; chưa có Redis vì local MVP chưa cần. Không deploy public trước khi thêm gateway/distributed quota. Không log URL provider vì chứa key và tọa độ. Uvicorn access log phải tắt để tránh query tìm kiếm. Không giữ lịch sử vị trí. User deletion /api/v1/me cascade ở PostgreSQL; UI xóa cục bộ riêng.

Navigation: lọc GPS accuracy >60m, lệch tuyến khi ba fix cách polyline >max(60m,2×accuracy), dừng stream khi background/end. ETA tuyến là snapshot provider; proposal cập nhật được so với thời gian còn lại ước tính (không phải map matching). Cooldown 5 phút và tiết kiệm >180s hoặc >15%. Không voice/turn-by-turn đầy đủ, không tự xác định rẽ tiếp theo. Cần kiểm thử thực địa và đánh giá sai số trên cầu/đường song song.

## Smart Departure (2026-10-24)
The additive app.departure module shares the SQLAlchemy metadata and database. FastAPI serves authenticated CRUD/inbox; python -m app.departure.worker is the only scheduler process. A DB lease, per-occurrence event uniqueness, persisted attempt budget and revision checks protect restart and concurrent edits. Windows uses an absolute-path SQLite database because the previous PostgreSQL endpoint was unavailable; PostgreSQL models and existing data remain intact. Flutter synchronizes via a per-installation hashed credential, caches read-only overview, and shows connectivity/worker heartbeat. Local notifications require device permission and a running app receiving events; FCM/APNs remains unconfigured. See SMART_DEPARTURE.md for deployment boundaries and testing.

## Integrated daily journeys (2026-10-24)

Flutter JourneyStore reuses SharedPreferences with a versioned document for independent
outbound/inbound selected-route snapshots, confirmed trip history and actual expenses.
No destructive conversion of legacy saved trips. Local writes are serialized and roll
back memory on failure. Schedule links use journey_id/direction in existing DB JSON;
server ownership always derives from the installation credential, never the local ID.
FastAPI wires Geoapify and Valhalla only, with bounded interactive routing requests and
persistent quota/backoff. TrafficDataProvider defaults to explicitly unavailable.
See JOURNEYS.md for storage scope, end-to-end flow and remaining push limitations.
