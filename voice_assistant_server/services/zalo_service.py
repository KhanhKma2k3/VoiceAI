import logging
import uuid
import os
import asyncio

import requests

from config import settings

logger = logging.getLogger(__name__)

OUTPUT_DIR = "outputs"
os.makedirs(OUTPUT_DIR, exist_ok=True)


async def generate_zalo_speech(text: str, speaker_id: str = "1", speed: float = 1.0) -> str:
    if not settings.ZALO_API_KEY:
        raise RuntimeError("ZALO_API_KEY chưa được cấu hình trong .env")

    # API Zalo AI chỉ chấp nhận speed trong khoảng [0.8, 1.2] -- ép cứng ở
    # đây để tránh gửi giá trị ngoài khoảng làm Zalo trả lỗi khó hiểu.
    safe_speed = max(0.8, min(1.2, speed))

    headers = {'apikey': settings.ZALO_API_KEY}
    data = {'input': text, 'speaker_id': speaker_id, 'speed': f"{safe_speed:.2f}"}

    response = requests.post("https://api.zalo.ai/v1/tts/synthesize", headers=headers, data=data, timeout=15)
    res_data = response.json()

    if res_data.get("error_code") == 0:
        async_url = res_data["data"]["url"]
        for _ in range(15):
            await asyncio.sleep(0.8)
            audio_res = requests.get(async_url, timeout=15)
            if audio_res.status_code == 200:
                filename = f"{uuid.uuid4()}.mp3"
                filepath = os.path.join(OUTPUT_DIR, filename)
                with open(filepath, 'wb') as f:
                    f.write(audio_res.content)
                return filepath
    logger.error("Loi Zalo TTS: %s", res_data)
    raise Exception(f"Lỗi Zalo: {res_data.get('error_message', 'Không thể tạo âm thanh')}")