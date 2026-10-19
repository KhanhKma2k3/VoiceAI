import logging
import re
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from config import settings
from database.database import get_db
from database import models, schemas
from services.auth_service import (
    GoogleAuthError,
    GoogleUnavailableError,
    as_utc,
    create_access_token,
    get_current_user,
    hash_password,
    hash_reset_code,
    verify_google_id_token,
    verify_password,
    verify_reset_code,
)
from services.email_service import send_reset_code

logger = logging.getLogger(__name__)
router = APIRouter(tags=["auth"])

USERNAME_RE = re.compile(r"^[A-Za-z0-9_.\-]{3,50}$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
MIN_PASSWORD_LEN = 6

RESET_MAX_ATTEMPTS = 5          # sai quá số lần này thì phải xin mã mới
RESET_RESEND_COOLDOWN_SEC = 60  # chống spam gửi mail


# ----------------------------- helpers -----------------------------
def _normalize_email(email: str | None) -> str:
    return (email or "").strip().lower()


def _token_response(user: models.User) -> dict:
    # `sub` PHẢI là username: get_current_user và relay-server-v2.js đều đọc sub.
    token = create_access_token({"sub": user.username})
    return {
        "access_token": token,
        "token_type": "bearer",
        "username": user.username,
        "email": user.email,
        "display_name": user.display_name,
    }


def _username_taken(db: Session, username: str) -> bool:
    return db.query(models.User).filter(func.lower(models.User.username) == username.lower()).first() is not None


def _unique_username_from_email(db: Session, email: str) -> str:
    base = re.sub(r"[^A-Za-z0-9_.\-]", "", email.split("@")[0])[:40] or "user"
    base = base.ljust(3, "0")
    candidate, n = base, 0
    while _username_taken(db, candidate):
        n += 1
        candidate = f"{base}{n}"
    return candidate


def _validate_new_password(password: str) -> None:
    if len(password) < MIN_PASSWORD_LEN:
        raise HTTPException(status_code=400, detail=f"Mật khẩu phải có ít nhất {MIN_PASSWORD_LEN} ký tự.")


# ----------------------------- register / login -----------------------------
@router.post("/register", response_model=schemas.TokenResponse)
def register(user_data: schemas.UserRegister, db: Session = Depends(get_db)):
    username = user_data.username.strip()
    email = _normalize_email(user_data.email) or None

    if not USERNAME_RE.match(username):
        raise HTTPException(
            status_code=400,
            detail="Tên tài khoản gồm 3-50 ký tự: chữ, số, dấu gạch dưới (_), chấm (.) hoặc gạch ngang (-), không chứa khoảng trắng hay '@'.",
        )
    _validate_new_password(user_data.password)
    if email is not None and not EMAIL_RE.match(email):
        raise HTTPException(status_code=400, detail="Email không hợp lệ.")

    if _username_taken(db, username):
        raise HTTPException(status_code=400, detail="Tên tài khoản đã tồn tại!")
    if email and db.query(models.User).filter(models.User.email == email).first():
        raise HTTPException(status_code=400, detail="Email này đã được đăng ký.")

    new_user = models.User(
        username=username,
        password_hash=hash_password(user_data.password),
        email=email,
    )
    db.add(new_user)
    try:
        db.commit()
    except IntegrityError:
        # Hai request đăng ký trùng nhau cùng lúc: ràng buộc UNIQUE của DB chặn lại.
        db.rollback()
        raise HTTPException(status_code=400, detail="Tên tài khoản hoặc email đã tồn tại!")
    db.refresh(new_user)
    return _token_response(new_user)


@router.post("/login", response_model=schemas.TokenResponse)
def login(user_data: schemas.UserLogin, db: Session = Depends(get_db)):
    identifier = user_data.username.strip()

    if "@" in identifier:
        user = db.query(models.User).filter(models.User.email == identifier.lower()).first()
    else:
        user = db.query(models.User).filter(models.User.username == identifier).first()

    if not user or not verify_password(user_data.password, user.password_hash):
        raise HTTPException(status_code=400, detail="Tài khoản hoặc mật khẩu không chính xác!")

    return _token_response(user)


@router.get("/me", response_model=schemas.UserProfile)
def me(current_user: models.User = Depends(get_current_user)):
    return {
        "username": current_user.username,
        "email": current_user.email,
        "display_name": current_user.display_name,
    }


# ----------------------------- Google -----------------------------
@router.post("/auth/google", response_model=schemas.TokenResponse)
def google_login(data: schemas.GoogleLoginRequest, db: Session = Depends(get_db)):
    try:
        info = verify_google_id_token(data.id_token)
    except GoogleUnavailableError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except GoogleAuthError as e:
        raise HTTPException(status_code=401, detail=str(e))

    google_id = info["sub"]
    email = _normalize_email(info["email"])
    name = (info.get("name") or "").strip()[:100] or None

    user = db.query(models.User).filter(models.User.google_id == google_id).first()
    if user is None:
        # Đã có tài khoản đăng ký bằng email này -> liên kết luôn (Google đã xác minh email).
        user = db.query(models.User).filter(models.User.email == email).first()
        if user is not None:
            user.google_id = google_id
            if not user.display_name:
                user.display_name = name
        else:
            user = models.User(
                username=_unique_username_from_email(db, email),
                # Tài khoản Google không có mật khẩu: lưu hash của chuỗi ngẫu nhiên
                # để cột NOT NULL hợp lệ và không ai đăng nhập bằng mật khẩu được.
                password_hash=hash_password(secrets.token_urlsafe(32)),
                email=email,
                display_name=name,
                google_id=google_id,
            )
            db.add(user)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=409, detail="Không thể tạo tài khoản Google, vui lòng thử lại.")
        db.refresh(user)

    return _token_response(user)


# ----------------------------- quên mật khẩu -----------------------------
@router.post("/forgot-password", response_model=schemas.MessageResponse)
def forgot_password(data: schemas.ForgotPasswordRequest, db: Session = Depends(get_db)):
    email = _normalize_email(data.email)
    if not EMAIL_RE.match(email):
        raise HTTPException(status_code=400, detail="Email không hợp lệ.")

    # Luôn trả cùng một thông báo dù email có tồn tại hay không, để không ai
    # dò được email nào đã đăng ký.
    generic = {
        "message": "Nếu email đã đăng ký, mã xác nhận đã được gửi. "
                   "Vui lòng kiểm tra hộp thư (kể cả mục Spam)."
    }

    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None:
        return generic

    now = datetime.now(timezone.utc)
    expire_delta = timedelta(minutes=settings.RESET_CODE_EXPIRE_MINUTES)

    if user.reset_code_expires is not None:
        sent_at = as_utc(user.reset_code_expires) - expire_delta
        wait = RESET_RESEND_COOLDOWN_SEC - int((now - sent_at).total_seconds())
        if wait > 0:
            raise HTTPException(status_code=429, detail=f"Vui lòng đợi {wait} giây trước khi yêu cầu mã mới.")

    code = f"{secrets.randbelow(10 ** 6):06d}"
    user.reset_code_hash = hash_reset_code(email, code)
    user.reset_code_expires = now + expire_delta
    user.reset_attempts = 0
    db.commit()

    if not send_reset_code(email, code):
        # Gửi mail thất bại: hủy mã vừa tạo để người dùng thử lại ngay được.
        user.reset_code_hash = None
        user.reset_code_expires = None
        db.commit()
        raise HTTPException(
            status_code=503,
            detail="Hiện chưa gửi được email xác nhận. Vui lòng thử lại sau ít phút.",
        )
    return generic


@router.post("/reset-password", response_model=schemas.MessageResponse)
def reset_password(data: schemas.ResetPasswordRequest, db: Session = Depends(get_db)):
    email = _normalize_email(data.email)
    code = data.code.strip()
    _validate_new_password(data.new_password)

    invalid = HTTPException(status_code=400, detail="Mã xác nhận không đúng hoặc đã hết hạn.")

    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None or not user.reset_code_hash or user.reset_code_expires is None:
        raise invalid

    def _invalidate() -> None:
        user.reset_code_hash = None
        user.reset_code_expires = None
        user.reset_attempts = 0
        db.commit()

    if as_utc(user.reset_code_expires) < datetime.now(timezone.utc):
        _invalidate()
        raise invalid

    if user.reset_attempts >= RESET_MAX_ATTEMPTS:
        _invalidate()
        raise HTTPException(status_code=400, detail="Bạn đã nhập sai quá nhiều lần. Hãy yêu cầu mã mới.")

    if not verify_reset_code(email, code, user.reset_code_hash):
        user.reset_attempts += 1
        db.commit()
        raise invalid

    user.password_hash = hash_password(data.new_password)
    _invalidate()  # mã chỉ dùng được 1 lần
    return {"message": "Đặt lại mật khẩu thành công. Hãy đăng nhập bằng mật khẩu mới."}
