import edge_tts
import uuid
import os

OUTPUT_DIR = "outputs"

os.makedirs(OUTPUT_DIR, exist_ok=True)

async def generate_speech(
    text: str,
    voice: str,
    rate: str
):
    filename = f"{uuid.uuid4()}.mp3"

    filepath = os.path.join(
        OUTPUT_DIR,
        filename
    )

    communicate = edge_tts.Communicate(
        text=text,
        voice=voice,
        rate=rate
    )

    await communicate.save(filepath)

    return filepath