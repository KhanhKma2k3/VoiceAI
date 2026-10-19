import hashlib
import hmac
import logging
from datetime import datetime, timedelta, timezone

import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from sqlalchemy.orm import Session

from config import settings
from database.database import get_db
from database import models

logger = logging.getLogger(__name__)

# HTTPBearer đọc header "Authorization: Bearer <token>" từ Flutter app.
# auto_error=False để mình tự trả lỗi 401 với message rõ ràng hơn.
_bearer_scheme = HTTPBearer(auto_error=False)


# bcrypt chỉ xử lý tối đa 72 byte đầu của mật khẩu. Tự cắt ở đây để hành vi
# giống nhau ở mọi phiên bản thư viện (bcrypt >= 5 ném lỗi nếu >72 byte).
#
# Dùng thư viện `bcrypt` trực tiếp thay cho `passlib`: passlib 1.7.4 không
# còn tương thích với bcrypt >= 4.1/5.0 và làm /register, /login trả lỗi 500.
# Hash cũ đã lưu trong DB (dạng "$2b$...") vẫn xác minh bình thường.
def _to_bcrypt_bytes(password: str) -> bytes:
    return password.encode("utf-8")[:72]


def hash_password(password: str) -> str:
    return bcrypt.hashpw(_to_bcrypt_bytes(password), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(_to_bcrypt_bytes(plain_password), hashed_password.encode("utf-8"))
    except (ValueError, TypeError):
        # Hash trong DB hỏng / không đúng định dạng bcrypt.
        return False


# ---------------------------------------------------------------------------
# Mã đặt lại mật khẩu (gửi qua email)
# ---------------------------------------------------------------------------
def hash_reset_code(email: str, code: str) -> str:
    """Băm mã 6 số bằng HMAC-SHA256 (khóa = JWT_SECRET_KEY, gắn kèm email).
    Mã chỉ có 1 triệu khả năng nên KHÔNG lưu mã gốc; cùng với giới hạn số lần
    thử + thời hạn ở routes/auth.py thì brute-force không khả thi."""
    msg = f"{email}:{code}".encode("utf-8")
    return hmac.new(settings.JWT_SECRET_KEY.encode("utf-8"), msg, hashlib.sha256).hexdigest()


def verify_reset_code(email: str, code: str, stored_hash: str) -> bool:
    return hmac.compare_digest(hash_reset_code(email, code), stored_hash)


def as_utc(dt: datetime) -> datetime:
    """SQLite trả datetime không có múi giờ -> coi là UTC để so sánh được."""
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


# ---------------------------------------------------------------------------
# Đăng nhập bằng Google
# ---------------------------------------------------------------------------
class GoogleAuthError(Exception):
    """Token Google không hợp lệ (sai audience, hết hạn, email chưa xác minh...)."""


class GoogleUnavailableError(Exception):
    """Chưa cấu hình GOOGLE_CLIENT_ID hoặc server không gọi được Google."""


def verify_google_id_token(raw_token: str) -> dict:
    """Xác minh `id_token` do app Flutter gửi lên, trả về thông tin người dùng
    (sub, email, name...). Token phải được cấp cho đúng GOOGLE_CLIENT_ID."""
    if not settings.GOOGLE_CLIENT_ID:
        raise GoogleUnavailableError("Server chưa cấu hình GOOGLE_CLIENT_ID.")

    from google.auth.exceptions import TransportError
    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token as google_id_token

    try:
        info = google_id_token.verify_oauth2_token(
            raw_token,
            google_requests.Request(),
            settings.GOOGLE_CLIENT_ID,
            # Đồng hồ điện thoại/PC lệch vài giây rất hay gây lỗi "Token used too early".
            clock_skew_in_seconds=30,
        )
    except TransportError as e:
        logger.warning("Khong ket noi duoc Google de xac minh token: %s", e)
        raise GoogleUnavailableError("Không kết nối được tới Google, thử lại sau.") from e
    except ValueError as e:
        logger.warning("Google id_token khong hop le: %s", e)
        raise GoogleAuthError("Token Google không hợp lệ hoặc đã hết hạn.") from e

    if not info.get("email") or not info.get("email_verified"):
        raise GoogleAuthError("Email Google chưa được xác minh.")
    return info


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=settings.ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def _decode_token(token: str) -> str:
    """Giải mã token, trả về username (subject). Raise HTTPException nếu token
    không hợp lệ / hết hạn."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token không hợp lệ hoặc đã hết hạn, vui lòng đăng nhập lại.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        username: str | None = payload.get("sub")
        if username is None:
            raise credentials_exception
        return username
    except JWTError as e:
        logger.warning("JWT decode that bai: %s", e)
        raise credentials_exception


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> models.User:
    """Dependency dùng cho mọi endpoint cần đăng nhập:

        @app.post("/chat")
        def chat(..., current_user: models.User = Depends(get_current_user)):
            ...

    Đây là điểm còn thiếu ở bản trước: JWT được TẠO ra ở /login, /register
    nhưng chưa hề được KIỂM TRA ở các endpoint khác. Giờ mọi endpoint dùng
    dependency này sẽ bắt buộc phải có Authorization: Bearer <token> hợp lệ.
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Thiếu token xác thực. Vui lòng đăng nhập.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    username = _decode_token(credentials.credentials)
    user = db.query(models.User).filter(models.User.username == username).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Người dùng không tồn tại.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def get_optional_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> models.User | None:
    """Giống get_current_user nhưng không bắt buộc đăng nhập — dùng cho các
    endpoint như /voice-assistant có thể cho phép khách vãng lai, nhưng nếu
    có gắn kèm token hợp lệ thì vẫn gắn được lịch sử vào đúng user."""
    if credentials is None:
        return None
    try:
        username = _decode_token(credentials.credentials)
    except HTTPException:
        return None
    return db.query(models.User).filter(models.User.username == username).first()
