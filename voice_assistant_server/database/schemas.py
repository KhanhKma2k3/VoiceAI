from pydantic import BaseModel
from datetime import datetime
from typing import Optional

class ChatRequest(BaseModel):
    user_id: Optional[int] = None
    message: str

class ConversationResponse(BaseModel):
    id: int
    user_message: str
    bot_reply: str
    created_at: datetime

    class Config:
        from_attributes = True

class TTSRequest(BaseModel):
    text: str
    voice: Optional[str] = "vi-VN-HoaiMyNeural"
    rate: Optional[str] = "+0%"
    pitch: Optional[str] = "+0Hz"

class UserRegister(BaseModel):
    username: str
    password: str
    email: Optional[str] = None

class UserLogin(BaseModel):
    # Có thể nhập tên tài khoản HOẶC email vào ô này.
    username: str
    password: str

class GoogleLoginRequest(BaseModel):
    id_token: str

class ForgotPasswordRequest(BaseModel):
    email: str

class ResetPasswordRequest(BaseModel):
    email: str
    code: str
    new_password: str

class MessageResponse(BaseModel):
    message: str

class UserProfile(BaseModel):
    username: str
    email: Optional[str] = None
    display_name: Optional[str] = None

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    username: str
    email: Optional[str] = None
    display_name: Optional[str] = None