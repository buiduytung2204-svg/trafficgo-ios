# TrafficGo performance audit — 23/10/2026

Nhánh làm việc: `audit/traffic-performance`, baseline `bd36263`. Không tạo lại project, không sửa commit/nhánh main, không push/merge/deploy, không thay key hoặc bật thanh toán. Backend chỉ khởi động lại cục bộ để đo bản sửa. File `.env` không chỉnh sửa; các request thật vẫn đi qua bộ đếm quota hiện có.

## Bottleneck và thứ tự xử lý

| Mức | Phát hiện xác nhận | Thay đổi / giới hạn |
|---|---|---|
| P0 | Map/traffic cùng proxy qua FastAPI và dùng quota TomTom; từng chạm daily budget | Giữ guard, phân biệt header `X-RateLimit-Bucket` cho backend/day/provider; không tăng budget trong audit |
| P0 | Bản cũ không có telemetry tách đường truyền/backend/provider | Thêm metrics bounded, endpoint auth `/api/v1/diagnostics`, `Server-Timing`, client timings và bảng local diagnostics |
| P0 | `no-store` cho mọi tile, quyền cache/proxy chưa được chứng minh đầy đủ | Giữ `no-store`, tắt disk cache; không suy diễn header nhà cung cấp là giấy phép lưu trữ |
| P1 | 4 request traffic giống nhau đồng thời thực sự tiêu thụ 4 upstream attempts | Coalescing chỉ khi đang in-flight, không giữ response sau khi task hoàn tất; đo sau sửa còn 1 upstream attempt |
| P1 | Timer cũ refresh traffic mỗi 120s khi app foreground dù không tương tác | Tạm dừng khi map bị route khác che, app background, traffic tắt, rate limited, đang gesture hoặc idle; navigation vẫn refresh ít nhất cách 120s khi không gesture |
| P1 | Nền TomTom chiếm một nửa các request của trace tile hai lớp | Tích hợp nguồn raster OSM trực tiếp có cấu hình; không chuyển tất cả người dùng sang máy chủ tile cộng đồng |
| P1 | Chưa có Valhalla adapter; quota TomTom có thể chặn router khác nếu dùng chung dependency | Thêm Valhalla, config/fallback rõ ràng; Valhalla không phụ thuộc daily budget TomTom; xe máy vẫn 422 |
| P2 | Chưa có số render thực trên browser/iPhone, chưa có Valhalla server | Thêm instrumentation và test shell trước/sau; không coi widget shell là render đầy đủ hoặc mock là Valhalla live |

## Baseline trước khi sửa

`docs/benchmarks/baseline-http.json` ghi 33 request thật qua backend bản gốc **trước khi sửa source**. Trace cố định 2×2 tile cho mỗi lớp, lần lượt open/pan/zoom/navigation_refresh (8 request/phase) và một route request. Đây là HTTP trace kiểm soát, không phải ghi lại gesture thực hoặc hành trình GPS. Trace chủ động gửi tile cả khi lặp viewport, không mô phỏng image cache của Flutter. Không truy cập tile OSM cộng đồng.

| Trace | Baseline p50 / p95 ms | Sau sửa p50 / p95 ms | Lỗi sau sửa |
|---|---:|---:|---:|
| Open | 453.50 / 2379.02 | 359.21 / 1842.96 | 0/8 |
| Pan | 366.70 / 1379.09 | 333.17 / 653.11 | 0/8 |
| Zoom | 421.18 / 945.83 | 323.60 / 677.75 | 0/8 |
| Navigation refresh trace | 394.99 / 951.81 | 337.93 / 599.37 | 0/8 |
| Route | 351.68 / 351.68 | 400.20 / 400.20 | 0/1 |

Mẫu rất nhỏ; p95 tile thực chất là giá trị lớn nhất trong 8 mẫu, route chỉ có một mẫu. Network, TLS/connection warmup, CDN và tải máy không được kiểm soát hoàn toàn. Không kết luận code làm mọi request nhanh hơn; route đã chậm hơn trong lần đo sau.

Phép thử request trùng riêng: `baseline-duplicates.json` có 4 incoming requests / 4 upstream attempts (đếm bằng chênh lệch budget trước/sau, backend bản gốc). Sau sửa, nhóm duplicates trong `after-http.json` có 4 incoming / 1 upstream; ba response có `X-Tile-Coalesced=true`. **Giảm 75% upstream requests trong tình huống này**, không phải giảm 75% cho mọi phiên. Toàn trace sau có 16 map + 17 traffic + 1 route = 34 attempts cho 37 incoming requests. Không cache tile giữa các nhóm trace.

Sau sửa, số đo tổng hợp theo nguồn: map upstream p50/p95 518.480/1573.890 ms và backend map 523.120/1581.168 ms; traffic upstream 299.464/345.601 và backend traffic 309.459/346.418 ms. Không lấy hiệu hai percentile để tính CPU overhead. Ví dụ một request có backend_total=1171.404 ms, upstream=1165.383 ms: phần lớn thời gian request đó là vòng đi-về provider, không phải xử lý FastAPI. Upstream timing gồm network/TLS/provider; không đo được nội bộ máy chủ TomTom. Response coalesced không có upstream call riêng, vì vậy upstream=0 ở waiter không có nghĩa TomTom tức thời.

## Render và phép đo frontend

- Không có browser khả dụng trong công cụ điều khiển phiên này; không có iPhone/macOS runner. Chưa đo full-map render, GPU, browser p50/p95 hay GPS navigation thật. JSON để `render_ms=null`, không điền số giả.
- Đã checkout baseline nguyên bản vào detached worktree ngoài project và chạy cùng `map_shell_benchmark_test.dart` cho hai phiên bản ở 390×844. Kết quả shell, bỏ mẫu warmup: baseline p50/p95 186.807/224.583 ms; lượt cuối sau sửa 115.883/123.780 ms. Năm mẫu/phiên bản, software-rendered shell **không imagery/network/GPS**; không dùng kết quả này để khẳng định map thật nhanh hơn.
- Runtime mới ghi số request/lỗi và p50/p95 theo phase, backend/upstream timing khi header có sẵn, first map-shell frame, first decoded tile và build/raster frame timings nếu nền tảng cung cấp. Tile decoded không phải toàn viewport đã sẵn sàng. Vào Settings → Chẩn đoán hiệu năng để xem/copy JSON. Không gửi số liệu lên server, không lưu tọa độ/URL/token.
- Để đo thật: tải mới trang, mở diagnostics sau từng bước open → pan → zoom → navigation, lưu JSON cục bộ. Dùng cùng viewport/zoom/device/network và ít nhất 30 phiên để có percentile hữu ích. Browser không cung cấp frame callback thì cần DevTools/Flutter DevTools; không thay missing samples bằng 0.

## OSM và giấy phép

Giữ mặc định `BASE_MAP_SOURCE=tomtom` để không đổi nền của app đang chạy. Các nguồn thêm mới:

1. `stadia_dev`: raster Alidade Smooth trực tiếp từ Stadia, chỉ Web tại localhost/127.0.0.1. [Tài liệu xác thực](https://docs.stadiamaps.com/authentication) cho phép development localhost không key nhưng có rate limit. [Giá](https://stadiamaps.com/pricing) ghi Free không commercial, không additional usage; chưa đăng ký tài khoản hoặc đổi plan. iOS/production cần key/domain/endpoint được cấp phép riêng, không dùng localhost bypass trên mobile. [Raster](https://docs.stadiamaps.com/raster/), [attribution](https://stadiamaps.com/attribution/) được dùng để cấu hình URL và liên kết attribution hiển thị trên map.
2. `osm_raster`: URL HTTPS của server tự quản hoặc nhà cung cấp được cấp phép, kèm attribution bắt buộc. Chặn host `tile.openstreetmap.org` và subdomain để không vô tình chạy benchmark/prefetch trên hạ tầng cộng đồng. Không triển khai tile server hoặc tải dataset trong audit. [OSM tile policy](https://operations.osmfoundation.org/policies/tiles/) yêu cầu attribution, identification và cache đúng quy định, đồng thời cấm bulk/prefetch và một số bot pan/zoom. Không coi dữ liệu OSM miễn phí đồng nghĩa mọi tile service miễn phí.
3. OpenFreeMap có [dịch vụ vector miễn phí](https://openfreemap.org/) và [hướng dẫn MapLibre](https://openfreemap.org/quick_start/), nhưng `vector_map_tiles` stable 8.0.0 hiện yêu cầu flutter_map ^7.0.2 trong khi app dùng ^8.3.2. Không ép dependency override hoặc thay renderer toàn app trong audit này.

[Trang điều khoản TomTom](https://docs.tomtom.com/legal/terms-and-conditions) đọc được không đưa ra đầy đủ quyền cache/proxy cho sản phẩm/tài khoản cụ thể. Vì vậy chưa bật persistent cache, CDN cache hay cross-session replay traffic; không khẳng định proxy/ghép TomTom với nguồn nền ngoài đã được cấp phép. Traffic trên nền ngoài bị gate mặc định: chỉ bật `EXTERNAL_BASEMAP_TRAFFIC_APPROVED=true` sau khi chủ tài khoản xác nhận quyền kết hợp dữ liệu. Bản TomTom mặc định giữ chức năng cũ. Coalescing chỉ gộp công việc đồng thời và không lưu nội dung sau response; đây không phải xác nhận pháp lý về proxy hiện có.

Quota local không chứng minh tài khoản vẫn trong free tier: quota theo SKU/account, các key/app khác và usage trước audit chưa được đối chiếu dashboard. Giữ Free/no overage như người dùng đã xác nhận, giữ daily guard, không bật dịch vụ có phí. Cần đặt hard cap theo dashboard trước production.

## Chạy lại và cấu hình

```powershell
# HTTP benchmark nhỏ, vẫn tiêu thụ quota thật qua backend hiện có
backend/.venv/Scripts/python scripts/benchmark_http.py --output docs/benchmarks/recheck-http.json

# UI OSM development, output riêng không ghi đè build đang phục vụ
cd mobile
flutter build web --no-wasm-dry-run --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=BASE_MAP_SOURCE=stadia_dev --output=build/web-osm-audit
# Chỉ sau xác nhận license ghép dữ liệu: thêm --dart-define=EXTERNAL_BASEMAP_TRAFFIC_APPROVED=true
flutter run -d edge --web-port 5174 --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=BASE_MAP_SOURCE=stadia_dev
```

Nếu dùng port 5174, chủ tài khoản cần thêm origin đó vào CORS local. Audit không tự sửa `.env`. Với nguồn self-host dùng `--dart-define=BASE_MAP_SOURCE=osm_raster`, `OSM_RASTER_URL` có {z}/{x}/{y}, `OSM_RASTER_ATTRIBUTION` có notice/license phù hợp. Không gửi app token sang nguồn nền ngoài. Không proxy tile OSM qua FastAPI.

Valhalla: đặt `ROUTING_PROVIDER=valhalla`, `VALHALLA_BASE_URL=http://127.0.0.1:8002` trỏ đến server thực do bạn quản lý; mặc định không có public demo endpoint và không tự host. `ROUTING_FALLBACK_TO_TOMTOM=false` mặc định; bật rõ ràng nếu muốn dùng TomTom khi Valhalla 502/503/504, vẫn chịu quota TomTom. Không fallback qua 429 để né rate limit. [Valhalla API](https://valhalla.github.io/valhalla/api/route/api-reference/) được dùng cho costing auto, OSRM GeoJSON và alternates; tránh toll/highway chỉ là preference, không bảo đảm loại bỏ tuyệt đối. Tuyến Valhalla gắn provider, traffic_aware=false và delay=null; không trình bày như traffic-aware ETA. Không cấp dữ liệu traffic riêng cho Valhalla, không xác minh motorcycle tại Việt Nam; vẫn khóa xe máy ở mọi adapter và endpoint. Server Valhalla/dữ liệu VN chưa có nên live validation bị chặn; adapter dùng MockTransport trong test.

## Kiểm tra và phần còn lại

Codemagic không sửa: Flutter pin, hai workflow, iOS deployment/signing vẫn giữ. Kiểm tra static/YAML không thay thế Xcode compile/signing. Xem PROGRESS.md cho lệnh và kết quả cuối. Cần người dùng xác nhận license cache/proxy/ghép dữ liệu, cung cấp Valhalla server và chạy browser/iPhone để hoàn tất nghiệm thu live. Không push/merge hoặc kích hoạt workflow cloud trong audit.
