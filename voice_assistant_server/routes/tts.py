import logging
import traceback
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from services.edge_tts_service import generate_speech
from services.zalo_service import generate_zalo_speech
from services.auth_service import get_current_user
from database import models

logger = logging.getLogger(__name__)
router = APIRouter(tags=["tts"])


class TTSRequest(BaseModel):
    text: str
    voice: Optional[str] = "zalo_female_north"
    rate: Optional[str] = "+0%"
    pitch: Optional[str] = "+0Hz"


_ZALO_SPEAKER_MAP = {
    "zalo_female_north": "1",
    "zalo_male_north": "2",
    "zalo_female_south": "3",
    "zalo_male_south": "4",
}


def _rate_percent_to_zalo_speed(rate_str: str) -> float:
    """Quy đổi rate dạng Edge-TTS ('+10%', '-30%'...) sang thang speed của
    Zalo AI (0.8 - 1.2, mặc định 1.0). Map tuyến tính: -50% -> 0.8,
    0% -> 1.0, +50% -> 1.2 -- khớp đúng khoảng slider (-50..50) bên client.
    """
    try:
        percent = float((rate_str or "0").replace("%", "").replace("+", ""))
    except (TypeError, ValueError):
        percent = 0.0
    speed = 1.0 + (percent * 0.004)
    return max(0.8, min(1.2, speed))


@router.get("/voices")
def get_voices():
    # Danh sách giọng đọc: thông tin công khai, không cần đăng nhập.
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


@router.post("/tts")
async def tts_endpoint(
    request: TTSRequest,
    current_user: models.User = Depends(get_current_user),
):
    try:
        voice_code = request.voice

        if voice_code.startswith("zalo_"):
            speaker_id = _ZALO_SPEAKER_MAP.get(voice_code, "1")
            zalo_speed = _rate_percent_to_zalo_speed(request.rate)
            logger.warning("TTS DEBUG: voice=%s rate=%s -> zalo_speed=%.2f", voice_code, request.rate, zalo_speed)
            try:
                audio_path = await generate_zalo_speech(request.text, speaker_id=speaker_id, speed=zalo_speed)
            except Exception as zalo_err:
                logger.warning("Zalo AI loi (%s), chuyen sang Edge-TTS...", zalo_err)
                fallback_voice = "vi-VN-NamMinhNeural" if speaker_id in ["2", "4"] else "vi-VN-HoaiMyNeural"
                audio_path = await generate_speech(request.text, voice=fallback_voice, rate=request.rate, pitch=request.pitch)
        else:
            audio_path = await generate_speech(request.text, voice=voice_code, rate=request.rate, pitch=request.pitch)

        return FileResponse(audio_path, media_type="audio/mpeg")
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Lỗi TTS: {str(e)}")