import os

from fastapi import APIRouter, UploadFile, File, Form

from services.whisper_service import save_upload, transcribe

router = APIRouter()


@router.post("/stt")
async def stt(
    audio: UploadFile = File(...),
    language: str = Form("vi"),
):
    filepath = await save_upload(audio)

    try:
        text = transcribe(filepath, language=language)
    finally:
        if os.path.exists(filepath):
            os.remove(filepath)

    return {"text": text}
