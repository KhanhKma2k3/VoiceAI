from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from database import models, schemas
from services.gemini_service import ask_gemini
from services.auth_service import get_current_user

router = APIRouter(tags=["chat"])


# Yêu cầu đăng nhập: Depends(get_current_user) sẽ chặn request không có
# Authorization: Bearer <token> hợp lệ (401) trước khi vào tới đây.
@router.post("/chat", response_model=schemas.ConversationResponse)
def chat_endpoint(
    request: schemas.ChatRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    reply = ask_gemini(request.message)

    db_chat = models.Conversation(
        user_id=current_user.id,
        user_message=request.message,
        bot_reply=reply,
    )
    db.add(db_chat)
    db.commit()
    db.refresh(db_chat)

    return db_chat
