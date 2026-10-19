"""
Cấu hình tập trung cho toàn bộ backend.
TUYỆT ĐỐI không hardcode API key / secret trong code nữa — mọi giá trị nhạy
cảm phải nằm trong file `.env` (không commit lên git) và được đọc qua đây.

Cách dùng ở nơi khác:
    from config import settings
    settings.GEMINI_API_KEY
"""
import os
import secrets
from dotenv import load_dotenv

# Nạp file .env nằm cùng thư mục với file này (nếu có)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))


def _require(name: str, default: str | None = None) -> str:
    """Đọc biến môi trường bắt buộc; báo lỗi rõ ràng ngay khi khởi động
    thay vì để lỗi mập mờ ở giữa request (fail fast)."""
    value = os.getenv(name, default)
    if not value:
        raise RuntimeError(
            f"Thiếu biến môi trường bắt buộc '{name}'. "
            f"Hãy tạo file .env (xem .env.example) và điền giá trị cho '{name}'."
        )
    return value


class Settings:
    # ---- Gemini AI ----
    GEMINI_API_KEY: str = _require("GEMINI_API_KEY")
    GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")

    # ---- Zalo AI TTS ----
    ZALO_API_KEY: str = os.getenv("ZALO_API_KEY", "")

    # ---- JWT / Auth ----
    # Nếu không đặt JWT_SECRET_KEY trong .env, tự sinh một key ngẫu nhiên khi
    # khởi động (an toàn hơn hardcode, nhưng token sẽ mất hiệu lực mỗi lần
    # restart server — nên vẫn khuyến nghị đặt cố định trong .env cho production).
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY") or secrets.token_hex(32)
    JWT_ALGORITHM: str = os.getenv("JWT_ALGORITHM", "HS256")
    ACCESS_TOKEN_EXPIRE_DAYS: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_DAYS", "30"))

    # ---- Đăng nhập Google ----
    # Web client ID (OAuth 2.0) tạo ở Google Cloud Console. App Flutter gửi
    # id_token lên, server xác minh token này có đúng dành cho client ID này.
    GOOGLE_CLIENT_ID: str = os.getenv("GOOGLE_CLIENT_ID", "")

    # ---- Gửi email (mã quên mật khẩu) ----
    # Nếu để trống SMTP_HOST, server KHÔNG gửi mail mà chỉ in mã ra log
    # (chỉ dùng khi phát triển). Với Gmail: SMTP_HOST=smtp.gmail.com,
    # SMTP_PORT=587, SMTP_PASSWORD = "Mật khẩu ứng dụng" (App Password).
    SMTP_HOST: str = os.getenv("SMTP_HOST", "")
    SMTP_PORT: int = int(os.getenv("SMTP_PORT", "587"))
    SMTP_USER: str = os.getenv("SMTP_USER", "")
    SMTP_PASSWORD: str = os.getenv("SMTP_PASSWORD", "")
    SMTP_FROM: str = os.getenv("SMTP_FROM", "") or os.getenv("SMTP_USER", "")
    RESET_CODE_EXPIRE_MINUTES: int = int(os.getenv("RESET_CODE_EXPIRE_MINUTES", "10"))

    # ---- Database ----
    # Mặc định vẫn dùng SQLite cho dev, nhưng có thể trỏ sang Postgres/MySQL
    # qua biến môi trường DATABASE_URL khi lên production, không cần sửa code.
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./app_voice.db")

    # ---- Dọn file tạm (audio outputs/uploads) ----
    FILE_RETENTION_HOURS: int = int(os.getenv("FILE_RETENTION_HOURS", "24"))
    CLEANUP_INTERVAL_MINUTES: int = int(os.getenv("CLEANUP_INTERVAL_MINUTES", "60"))

    # ---- Logging ----
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")


settings = Settings()
import hashlib
print("[JWT] fingerprint:", hashlib.sha256(settings.JWT_SECRET_KEY.encode()).hexdigest()[:8])