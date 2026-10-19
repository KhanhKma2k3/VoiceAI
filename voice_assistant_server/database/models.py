from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey
from sqlalchemy.sql import func
from database.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # --- Các cột phục vụ đăng nhập email / Google / quên mật khẩu ---
    # (khớp với run_light_migrations trong database/database.py)
    email = Column(String(255), unique=True, index=True, nullable=True)
    display_name = Column(String(100), nullable=True)
    google_id = Column(String(64), unique=True, index=True, nullable=True)

    # Mã đặt lại mật khẩu: chỉ lưu bản băm (HMAC), không lưu mã gốc.
    reset_code_hash = Column(String, nullable=True)
    reset_code_expires = Column(DateTime(timezone=True), nullable=True)
    reset_attempts = Column(Integer, nullable=False, default=0, server_default="0")

    def __init__(self, username: str, password_hash: str, **kwargs):
        super().__init__(**kwargs)
        self.username = username
        self.password_hash = password_hash


class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)  # Có thể null nếu chưa login
    user_message = Column(Text, nullable=False)
    bot_reply = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
