from fastapi import APIRouter, Form
from services.gemini_service import ask_gemini

router = APIRouter()

@router.post("/chat")
async def chat_with_ai(
    message: str = Form(...),
):
    reply = ask_gemini(message)
    return {
        "user_message": message,
        "bot_reply": reply
    }