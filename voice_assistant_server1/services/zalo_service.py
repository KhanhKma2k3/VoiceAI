import requests
import uuid
import os
import asyncio

OUTPUT_DIR = "outputs"
os.makedirs(OUTPUT_DIR, exist_ok=True)

ZALO_API_KEY = "aL7ESnlFR14bINBe3twyJxmchhMIymGb"

async def generate_zalo_speech(text: str, speaker_id: str = "1") -> str:
    headers = {'apikey': ZALO_API_KEY}
    data = {'input': text, 'speaker_id': speaker_id, 'speed': '1.0'}
    
    response = requests.post("https://api.zalo.ai/v1/tts/synthesize", headers=headers, data=data)
    res_data = response.json()
    
    if res_data.get("error_code") == 0:
        async_url = res_data["data"]["url"]
        for _ in range(15):
            await asyncio.sleep(0.8)
            audio_res = requests.get(async_url)
            if audio_res.status_code == 200:
                filename = f"{uuid.uuid4()}.mp3"
                filepath = os.path.join(OUTPUT_DIR, filename)
                with open(filepath, 'wb') as f:
                    f.write(audio_res.content)
                return filepath
    raise Exception(f"Lỗi Zalo: {res_data.get('error_message', 'Không thể tạo âm thanh')}")