"""Gửi email (dùng cho mã quên mật khẩu) qua SMTP — tối ưu cho Gmail.

Cấu hình trong .env (xem .env.example):
    SMTP_HOST=smtp.gmail.com
    SMTP_PORT=587            # 587 = STARTTLS, 465 = SSL
    SMTP_USER=ten@gmail.com
    SMTP_PASSWORD=xxxx xxxx xxxx xxxx   # "Mật khẩu ứng dụng" 16 ký tự, KHÔNG phải mật khẩu Gmail

Gmail KHÔNG còn cho đăng nhập SMTP bằng mật khẩu thường. Bắt buộc:
    1. Bật Xác minh 2 bước:  https://myaccount.google.com/security
    2. Tạo Mật khẩu ứng dụng: https://myaccount.google.com/apppasswords
"""
import logging
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formataddr

from config import settings

logger = logging.getLogger(__name__)

APP_NAME = "Trợ Lý Âm Thanh"


def is_email_configured() -> bool:
    return bool(settings.SMTP_HOST and settings.SMTP_USER and settings.SMTP_PASSWORD)


def _clean_password(raw: str) -> str:
    # Google hiển thị App Password dạng "abcd efgh ijkl mnop" (có dấu cách);
    # dán nguyên vào .env vẫn đăng nhập được nếu bỏ hết khoảng trắng.
    return "".join(raw.split())


def send_email(to_address: str, subject: str, body: str) -> bool:
    """Gửi 1 email văn bản. Trả về True nếu gửi thành công, False nếu thất bại
    (lý do được ghi vào log server, KHÔNG ghi mã/mật khẩu vào log)."""
    if not is_email_configured():
        logger.error(
            "Chua cau hinh SMTP (can SMTP_HOST, SMTP_USER, SMTP_PASSWORD trong .env) "
            "-> khong gui duoc email toi %s",
            to_address,
        )
        return False

    # Gmail yêu cầu địa chỉ From trùng với tài khoản đăng nhập SMTP (hoặc alias
    # đã khai báo); nếu không, Gmail tự ghi đè thành SMTP_USER.
    from_address = settings.SMTP_FROM or settings.SMTP_USER

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = formataddr((APP_NAME, from_address))
    msg["To"] = to_address
    msg.set_content(body)

    password = _clean_password(settings.SMTP_PASSWORD)
    context = ssl.create_default_context()

    try:
        if settings.SMTP_PORT == 465:
            with smtplib.SMTP_SSL(settings.SMTP_HOST, settings.SMTP_PORT, timeout=20, context=context) as smtp:
                smtp.login(settings.SMTP_USER, password)
                smtp.send_message(msg)
        else:
            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=20) as smtp:
                smtp.ehlo()
                smtp.starttls(context=context)
                smtp.ehlo()
                smtp.login(settings.SMTP_USER, password)
                smtp.send_message(msg)
        logger.info("Da gui email '%s' toi %s", subject, to_address)
        return True
    except smtplib.SMTPAuthenticationError as e:
        logger.error(
            "Gmail tu choi dang nhap SMTP (%s). Kiem tra: (1) SMTP_USER dung dia chi Gmail, "
            "(2) SMTP_PASSWORD la 'Mat khau ung dung' 16 ky tu (khong phai mat khau Gmail), "
            "(3) da bat Xac minh 2 buoc.",
            e.smtp_code,
        )
    except smtplib.SMTPRecipientsRefused:
        logger.error("Dia chi nguoi nhan bi tu choi: %s", to_address)
    except (smtplib.SMTPException, OSError):
        logger.exception("Gui email that bai toi %s (kiem tra SMTP_HOST/SMTP_PORT/mang)", to_address)
    return False


def send_reset_code(to_address: str, code: str) -> bool:
    body = (
        f"Xin chào,\n\n"
        f"Mã đặt lại mật khẩu của bạn là: {code}\n\n"
        f"Mã có hiệu lực trong {settings.RESET_CODE_EXPIRE_MINUTES} phút và chỉ dùng được một lần.\n"
        f"Nếu bạn không yêu cầu đặt lại mật khẩu, hãy bỏ qua email này — tài khoản của bạn vẫn an toàn.\n\n"
        f"— {APP_NAME}"
    )
    return send_email(to_address, f"Mã đặt lại mật khẩu - {APP_NAME}", body)
