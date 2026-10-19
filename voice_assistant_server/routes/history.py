from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from database import models, schemas
from services.auth_service import get_current_user

router = APIRouter(tags=["history"])


@router.get("/history", response_model=list[schemas.ConversationResponse])
def get_history(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    # Trước đây endpoint này trả về TOÀN BỘ lịch sử của MỌI user - rò rỉ dữ
    # liệu. Giờ luôn lọc theo current_user.id, mỗi người chỉ thấy lịch sử
    # của chính mình.
    return (
        db.query(models.Conversation)
        .filter(models.Conversation.user_id == current_user.id)
        .order_by(models.Conversation.id.desc())
        .all()
    )
