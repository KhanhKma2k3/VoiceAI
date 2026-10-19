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

class UserLogin(BaseModel):
    username: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    username: str