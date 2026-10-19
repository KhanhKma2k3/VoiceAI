import os
import traceback
from typing import Optional
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel

# Import các thành phần CSDL
from database.database import Base, engine, get_db
from database import models, schemas

# Import các dịch vụ TTS & STT
from services.gemini_service import ask_gemini
from services.edge_tts_service import generate_speech
from services.zalo_service import generate_zalo_speech
from services.stt_service import save_upload, transcribe
#from services.audio_effects import apply_audio_effect

#đăng nhập 
from services.auth_service import hash_password, verify_password, create_access_token
# Khởi tạo bảng dữ liệu
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="Voice Assistant Backend")

# Schema dữ liệu TTS
class TTSRequest(BaseModel):
    text: str
    voice: Optional[str] = "zalo_female_north"
    rate: Optional[str] = "+0%"
    pitch: Optional[str] = "+0Hz"

# 1. API Trò chuyện AI
@app.post("/chat", response_model=schemas.ConversationResponse)
def chat_endpoint(request: schemas.ChatRequest, db: Session = Depends(get_db)):
    reply = ask_gemini(request.message)
    
    db_chat = models.Conversation(
        user_id=request.user_id,
        user_message=request.message,
        bot_reply=reply
    )
    db.add(db_chat)
    db.commit()
    db.refresh(db_chat)
    
    return db_chat

# 2. API Lấy danh sách giọng đọc
@app.get("/voices")
def get_voices():
    return [
        {"name": "🇻🇳 Bắc - Nữ Truyền Cảm (Zalo)", "code": "zalo_female_north"},
        {"name": "🇻🇳 Bắc - Nam Ấm Áp (Zalo)", "code": "zalo_male_north"},
        {"name": "🇻🇳 Nam - Nữ Trong Trẻo (Zalo)", "code": "zalo_female_south"},
        {"name": "🇻🇳 Nam - Nam Trầm (Zalo)", "code": "zalo_male_south"},
        {"name": "🇻🇳 Bắc - Nữ Hoài My (Edge)", "code": "vi-VN-HoaiMyNeural"},
        {"name": "🇻🇳 Bắc - Nam Nam Minh (Edge)", "code": "vi-VN-NamMinhNeural"},
        {"name": "🌐 Đa Ngôn Ngữ - Nữ Phương Âm (Edge)", "code": "vi-VN-PhuongAnhNeural"},
        {"name": "🇺🇸 Tiếng Anh - Nữ Jenny (US)", "code": "en-US-JennyNeural"},
        {"name": "🇺🇸 Tiếng Anh - Nam Guy (US)", "code": "en-US-GuyNeural"},
        {"name": "🇬🇧 Tiếng Anh - Nữ Sonia (UK)", "code": "en-GB-SoniaNeural"},
    ]

# 3. API Text-to-Speech (Zalo AI + Fallback Edge-TTS)
@app.post("/tts")
async def tts_endpoint(request: TTSRequest):
    try:
        voice_code = request.voice
        
        if voice_code.startswith("zalo_"):
            speaker_map = {
                "zalo_female_north": "1",
                "zalo_male_north": "2",
                "zalo_female_south": "3",
                "zalo_male_south": "4"
            }
            speaker_id = speaker_map.get(voice_code, "1")
            
            try:
                audio_path = await generate_zalo_speech(request.text, speaker_id=speaker_id)
            except Exception as zalo_err:
                print(f"⚠️ Zalo AI lỗi ({zalo_err}), chuyển sang Edge-TTS...")
                fallback_voice = "vi-VN-NamMinhNeural" if speaker_id in ["2", "4"] else "vi-VN-HoaiMyNeural"
                audio_path = await generate_speech(request.text, voice=fallback_voice)
        else:
            audio_path = await generate_speech(request.text, voice=voice_code)

        return FileResponse(audio_path, media_type="audio/mpeg")
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Lỗi TTS: {str(e)}")

# 4. API Speech-to-Text (Faster-Whisper)
@app.post("/stt")
async def speech_to_text_endpoint(file: UploadFile = File(...)):
    try:
        if not file or not file.filename:
            raise HTTPException(status_code=400, detail="File không hợp lệ")

        filepath = await save_upload(file)
        text = transcribe(filepath, language="vi")
        
        if os.path.exists(filepath):
            os.remove(filepath)
            
        return {"text": text}
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Lỗi STT: {str(e)}")

# 5. API Lịch sử trò chuyện
@app.get("/history", response_model=list[schemas.ConversationResponse])
def get_history(db: Session = Depends(get_db)):
    return db.query(models.Conversation).order_by(models.Conversation.id.desc()).all()

@app.post("/register")
def register(user_data: schemas.UserRegister, db: Session = Depends(get_db)):
    # Kiểm tra user tồn tại
    existing_user = db.query(models.User).filter(models.User.username == user_data.username).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Tên tài khoản đã tồn tại!")
    
    # Tạo user mới
    new_user = models.User(
        username=user_data.username,
        password_hash=hash_password(user_data.password)
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    token = create_access_token({"sub": new_user.username})
    return {"access_token": token, "token_type": "bearer", "username": new_user.username}

@app.post("/login")
def login(user_data: schemas.UserLogin, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.username == user_data.username).first()
    if not user or not verify_password(user_data.password, user.password_hash):
        raise HTTPException(status_code=400, detail="Tài khoản hoặc mật khẩu không chính xác!")
    
    token = create_access_token({"sub": user.username})
    return {"access_token": token, "token_type": "bearer", "username": user.username}


@app.post("/voice-assistant")
async def voice_assistant_endpoint(
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    try:
        if not file or not file.filename:
            raise HTTPException(status_code=400, detail="File không hợp lệ")

        # 1. Chuyển Giọng nói -> Văn bản (STT)
        filepath = await save_upload(file)
        user_text = transcribe(filepath, language="vi")
        
        if os.path.exists(filepath):
            os.remove(filepath)

        if not user_text:
            return {
                "user_text": "",
                "bot_reply": "Tôi không nghe rõ, bạn nói lại được không?",
                "audio_url": None
            }

        # 2. Xử lý Từ khóa Điều khiển (Voice Commands)
        clean_text = user_text.lower().strip()
        
        if "xóa lịch sử" in clean_text or "làm mới" in clean_text:
            bot_reply = "Đã làm mới phiên trò chuyện của bạn."
        elif "dừng lại" in clean_text or "tắt thoại" in clean_text:
            bot_reply = "Đã tắt chế độ giọng nói rảnh tay."
        else:
            # 3. Gửi sang Gemini AI
            bot_reply = ask_gemini(user_text)

            # Lưu vào CSDL
            db_chat = models.Conversation(
                user_id=None,
                user_message=user_text,
                bot_reply=bot_reply
            )
            db.add(db_chat)
            db.commit()

        # 4. Chuyển Câu trả lời AI -> File âm thanh (TTS)
        audio_path = await generate_speech(bot_reply, voice="vi-VN-HoaiMyNeural")

        return FileResponse(
            audio_path, 
            media_type="audio/mpeg",
            headers={
                "X-User-Text": user_text.encode('utf-8').decode('latin1'),
                "X-Bot-Reply": bot_reply.encode('utf-8').decode('latin1')
            }
        )

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Lỗi Voice Assistant: {str(e)}")