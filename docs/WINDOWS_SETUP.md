# Windows

Đã phát hiện Python 3.14.2, Git 2.52.0, winget. Flutter/Dart ban đầu không trong PATH. SDK được tải từ stable repository vào C:\Users\tungb\trafficgo-tools\flutter; xem PROGRESS để biết kiểm tra cuối.

Nếu máy khác thiếu công cụ:

```powershell
winget install --id Git.Git -e
winget install --id Python.Python.3.11 -e
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git C:\src\flutter
$env:Path = 'C:\src\flutter\bin;' + $env:Path
flutter doctor -v
flutter --version
dart --version
```

Cài VS Code Flutter extension, Android Studio/SDK nếu dùng emulator. Không cần Xcode trên Windows. Web dùng để kiểm tra UI; GPS trên browser có yêu cầu secure context. iOS plugins và GPS phải kiểm tra thật trên iPhone qua CI.

```powershell
python -m venv backend/.venv
backend/.venv/Scripts/python -m pip install -r backend/requirements.txt
Copy-Item backend/.env.example backend/.env
# Sửa .env cục bộ, tuyệt đối không commit.
cd backend
.venv/Scripts/python -m alembic upgrade head
.venv/Scripts/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-access-log
```

Thay bước Copy-Item bằng `powershell -File scripts/bootstrap_env.ps1` từ root nếu muốn tạo access token ngẫu nhiên cục bộ. Script không ghi đè .env đã có và không in token ra log. Tự điền TomTom key, CORS và database; không gửi nội dung .env vào chat.

PostgreSQL: cài local hoặc Docker Desktop, đặt POSTGRES_PASSWORD trước docker compose up -d, cập nhật DATABASE_URL khớp. CORS_ORIGINS là JSON array chỉ chứa origin dev cần dùng. Không dùng * với token. Từ root:

```powershell
cd mobile
flutter pub get
flutter run -d edge --web-port 5173 --dart-define=API_BASE_URL=http://localhost:8000
```

Đặt CORS_ORIGINS=["http://localhost:5173"] trong backend .env. Khi test Android emulator dùng 10.0.2.2 thay localhost; chỉ cho cleartext trong manifest debug. Production luôn HTTPS.
