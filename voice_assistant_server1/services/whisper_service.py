
import os
import uuid

import torch
from faster_whisper import WhisperModel

MODEL_SIZE = "small"

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
COMPUTE_TYPE = "float16" if DEVICE == "cuda" else "int8"

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

# Model được load 1 lần duy nhất khi server khởi động,
# tránh load lại mỗi request (rất tốn thời gian).
model = WhisperModel(
    MODEL_SIZE,
    device=DEVICE,
    compute_type=COMPUTE_TYPE,
)


async def save_upload(file) -> str:
    ext = os.path.splitext(file.filename)[1] or ".wav"
    filename = f"{uuid.uuid4()}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)

    with open(filepath, "wb") as f:
        content = await file.read()
        f.write(content)

    return filepath


def transcribe(filepath: str, language: str = "vi") -> str:
    segments, info = model.transcribe(
        filepath,
        language=language,
        beam_size=5,
        vad_filter=True,  # loại bỏ khoảng lặng, giúp nhanh + chính xác hơn
    )

    text = "".join(segment.text for segment in segments)

    return text.strip()