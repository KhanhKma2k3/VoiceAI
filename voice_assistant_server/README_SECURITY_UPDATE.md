# Đã cập nhật: bảo mật + dọn dẹp + hạ tầng

## Việc BẠN cần làm thủ công trước khi chạy (quan trọng nhất)

1. **Thu hồi 2 API key cũ ngay lập tức** (đã bị lộ trong code cũ):
   - Gemini: vào https://aistudio.google.com/apikey → xoá key cũ, tạo key mới.
   - Zalo AI: vào Zalo AI Console → thu hồi key cũ, tạo key mới.
2. Tạo file `.env` (copy từ `.env.example`) trong thư mục `voice_assistant_server/`,
   điền key mới + một `JWT_SECRET_KEY` ngẫu nhiên mạnh:
   ```bash
   cp .env.example .env
   python -c "import secrets; print(secrets.token_hex(32))"   # dán vào JWT_SECRET_KEY
   ```
3. Cài lại dependency (đã bổ sung passlib, python-jose, google-genai, sqlalchemy...):
   ```bash
   pip install -r requirements.txt
   ```
4. `app_voice.db` cũ vẫn dùng được (schema không đổi), nhưng khuyến nghị xoá đi
   tạo lại để test sạch: `rm app_voice.db`.

## Những gì đã thay đổi

### (1) API key
- Không còn hardcode key nào trong source. Toàn bộ đọc qua `config.py` (dùng `python-dotenv`).
- `.env` đã được thêm vào `.gitignore`.

### (2) JWT thực sự bảo vệ endpoint
- `services/auth_service.py` có thêm `get_current_user` (dependency FastAPI) — giải mã & xác thực token, tra user trong DB.
- Các endpoint `/chat`, `/tts`, `/stt`, `/history`, `/voice-assistant` giờ **bắt buộc** header:
  ```
  Authorization: Bearer <token>
  ```
  Không có/token sai/hết hạn → trả lỗi `401`.
- `/history` giờ **chỉ trả lịch sử của user đang đăng nhập** (trước đây trả toàn bộ user).
- `Conversation.user_id` giờ được gắn đúng người dùng thật thay vì `None`.
- App Flutter (`lib/services/api_service.dart`) đã được cập nhật để tự đính kèm token đã lưu (`SharedPreferences`) vào mọi request cần đăng nhập.

### (3) Dọn code trùng/rác
- Gộp toàn bộ logic API vào `routes/` (trước đây viết trùng ở cả `main.py` lẫn `routes/__init__.py`, còn `routes/tts.py` cũng trùng nội dung). `main.py` giờ chỉ còn `include_router(...)`.
- Xoá `services/whisper_service.py` (trùng gần như 100% với `stt_service.py`).
- Xoá đoạn code chết (unreachable) trong `stt_service.py` sau câu lệnh `return`.
- Xoá 2 file Flutter rỗng, không dùng: `lib/models/history_item.dart`, `lib/screens/home_screen.dart`.

### (4) Hạ tầng
- **Database**: đọc `DATABASE_URL` từ `.env` — mặc định vẫn SQLite cho dev, đổi sang Postgres/MySQL cho production chỉ cần sửa `.env`, không sửa code.
- **Dọn file audio tạm**: `services/cleanup_service.py` chạy nền (task trong `lifespan` của FastAPI), tự xoá file trong `outputs/` và `uploads/` cũ hơn `FILE_RETENTION_HOURS` (mặc định 24h), lặp mỗi `CLEANUP_INTERVAL_MINUTES` phút (mặc định 60).
- **Logging**: `logging_config.py` thay thế toàn bộ `print()` bằng `logging` có timestamp + level, cấu hình qua `LOG_LEVEL`.
- **Test**: thêm `tests/test_auth.py`, `tests/test_protected_endpoints.py` dùng `pytest` + `TestClient`, chạy bằng:
  ```bash
  pytest
  ```
  (test dùng SQLite riêng `test_app_voice.db`, tự xoá sau khi chạy xong; mock Gemini nên không cần key thật/mạng lúc test).

## Lưu ý còn lại (chưa làm, gợi ý cho lần sau)
- Chuyển IP LAN hardcode trong `api_service.dart` sang cấu hình build-time (`--dart-define`) khi build bản release thật.
- Bật HTTPS cho backend khi deploy thật (hiện là HTTP thuần).
- Cân nhắc thêm rate-limiting (vd. `slowapi`) để tránh spam Gemini/Zalo.
