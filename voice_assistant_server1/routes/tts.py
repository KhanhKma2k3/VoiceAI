from fastapi import APIRouter, Form
from fastapi.responses import FileResponse
from services.edge_tts_service import generate_speech

router = APIRouter()

@router.post("/tts")
async def tts(
    text: str = Form(...),
    voice: str = Form("vi-VN-HoaiMyNeural"),
    rate: str = Form("+0%"),
):
    file_path = await generate_speech(
        text=text,
        voice=voice,
        rate=rate,
    )

    return FileResponse(
        file_path,
        media_type="audio/mpeg",
        filename="speech.mp3",
    )