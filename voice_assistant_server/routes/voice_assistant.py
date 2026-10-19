import os
import traceback

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from database.database import get_db
from database import models
from services.stt_service import save_upload, transcribe
from services.gemini_service import ask_gemini
from services.edge_tts_service import generate_speech
from services.auth_service import get_current_user

router = APIRouter(tags=["voice-assistant"])


@router.post("/voice-assistant")
async def voice_assistant_endpoint(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    try:
        if not file or not file.filename:
            raise HTTPException(status_code=400, detail="File không hợp lệ")

        # 1. Giọng nói -> Văn bản (STT)
        filepath = await save_upload(file)
        try:
            user_text = transcribe(filepath, language="vi")
        finally:
            if os.path.exists(filepath):
                os.remove(filepath)

        if not user_text:
            return {
                "user_text": "",
                "bot_reply": "Tôi không nghe rõ, bạn nói lại được không?",
                "audio_url": None,
            }

        # 2. Xử lý từ khoá điều khiển
        clean_text = user_text.lower().strip()

        if "xóa lịch sử" in clean_text or "làm mới" in clean_text:
            bot_reply = "Đã làm mới phiên trò chuyện của bạn."
        elif "dừng lại" in clean_text or "tắt thoại" in clean_text:
            bot_reply = "Đã tắt chế độ giọng nói rảnh tay."
        else:
            # 3. Gửi sang Gemini AI
            bot_reply = ask_gemini(user_text)

            db_chat = models.Conversation(
                user_id=current_user.id,
                user_message=user_text,
                bot_reply=bot_reply,
            )
            db.add(db_chat)
            db.commit()

        # 4. Câu trả lời -> âm thanh
        audio_path = await generate_speech(bot_reply, voice="vi-VN-HoaiMyNeural")

        return FileResponse(
            audio_path,
            media_type="audio/mpeg",
            headers={
                "X-User-Text": user_text.encode('utf-8').decode('latin1'),
                "X-Bot-Reply": bot_reply.encode('utf-8').decode('latin1'),
            },
        )

    except HTTPException:
        raise
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Lỗi Voice Assistant: {str(e)}")
