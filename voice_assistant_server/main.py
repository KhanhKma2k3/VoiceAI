import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from logging_config import setup_logging
from database.database import Base, engine, run_light_migrations
from database import models  # noqa: F401  (đăng ký model với Base trước khi create_all)
from services.cleanup_service import cleanup_loop
from routes import auth, ai_chat, tts, stt, history, voice_assistant

setup_logging()
logger = logging.getLogger(__name__)

# Khởi tạo bảng dữ liệu
Base.metadata.create_all(bind=engine)
run_light_migrations(engine)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Chạy tác vụ dọn file audio cũ (outputs/, uploads/) song song với server,
    # thay vì để file tồn đọng vô hạn như trước.
    cleanup_task = asyncio.create_task(cleanup_loop())
    logger.info("Server khoi dong, cleanup task da duoc bat.")
    yield
    cleanup_task.cancel()


app = FastAPI(title="Voice Assistant Backend", lifespan=lifespan)

# Mỗi nhóm endpoint giờ nằm gọn trong routes/, không còn định nghĩa trùng lặp
# ở cả main.py lẫn routes/ như bản trước.
app.include_router(auth.router)
app.include_router(ai_chat.router)
app.include_router(tts.router)
app.include_router(stt.router)
app.include_router(history.router)
app.include_router(voice_assistant.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
