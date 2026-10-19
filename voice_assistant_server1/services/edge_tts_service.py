import edge_tts
import uuid
import os

OUTPUT_DIR = "outputs"
os.makedirs(OUTPUT_DIR, exist_ok=True)

async def generate_speech(
    text: str, 
    voice: str = "vi-VN-HoaiMyNeural", 
    rate: str = "+0%", 
    pitch: str = "+0Hz"
):
    filename = f"{uuid.uuid4()}.mp3"
    filepath = os.path.join(OUTPUT_DIR, filename)

    # Đảm bảo chuỗi rate và pitch đúng định dạng của Edge-TTS
    formatted_rate = rate if rate.endswith("%") else f"{rate}%"
    if not (formatted_rate.startswith("+") or formatted_rate.startswith("-")):
        formatted_rate = f"+{formatted_rate}"

    formatted_pitch = pitch if pitch.endswith("Hz") else f"{pitch}Hz"
    if not (formatted_pitch.startswith("+") or formatted_pitch.startswith("-")):
        formatted_pitch = f"+{formatted_pitch}"

    communicate = edge_tts.Communicate(
        text=text,
        voice=voice,
        rate=formatted_rate,
        pitch=formatted_pitch,
    )

    await communicate.save(filepath)
    return filepath