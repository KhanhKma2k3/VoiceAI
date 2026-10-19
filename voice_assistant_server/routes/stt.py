import logging
import os
import traceback

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File

from services.stt_service import save_upload, transcribe
from services.auth_service import get_current_user
from database import models

logger = logging.getLogger(__name__)
router = APIRouter(tags=["stt"])


@router.post("/stt")
async def speech_to_text_endpoint(
    file: UploadFile = File(...),
    current_user: models.User = Depends(get_current_user),
):
    try:
        if not file or not file.filename:
            raise HTTPException(status_code=400, detail="File không hợp lệ")

        filepath = await save_upload(file)
        try:
            text = transcribe(filepath, language="vi")
        finally:
            if os.path.exists(filepath):
                os.remove(filepath)

        return {"text": text}
    except HTTPException:
        raise
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Lỗi STT: {str(e)}")
