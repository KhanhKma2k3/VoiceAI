import logging
import os
import uuid

import torch
from faster_whisper import WhisperModel

logger = logging.getLogger(__name__)

MODEL_SIZE = "small"

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
COMPUTE_TYPE = "float16" if DEVICE == "cuda" else "int8"

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

# Model được load 1 lần duy nhất khi server khởi động (module-level singleton),
# tránh load lại mỗi request - rất tốn thời gian/RAM.
model = WhisperModel(
    MODEL_SIZE,
    device=DEVICE,
    compute_type=COMPUTE_TYPE,
)


async def save_upload(file) -> str:
    ext = os.path.splitext(file.filename)[1] or ".m4a"
    filename = f"{uuid.uuid4()}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)

    with open(filepath, "wb") as f:
        content = await file.read()
        f.write(content)

    logger.info("Da nhan file: %s (%d bytes)", filepath, os.path.getsize(filepath))
    return filepath


def transcribe(filepath: str, language: str = "vi") -> str:
    logger.info("Dang xu ly file: %s", filepath)

    segments, info = model.transcribe(
        filepath,
        language=language,
        beam_size=1,                        # beam_size=1 để tránh kẹt loop trên câu ngắn
        best_of=1,
        vad_filter=False,
        condition_on_previous_text=False,   # tránh bỏ sót văn bản khi có khoảng lặng dài
        temperature=0.0,
    )

    results = [segment.text for segment in segments]
    text = "".join(results).strip()
    logger.info("Ket qua STT: '%s'", text)
    return text
