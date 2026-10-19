import os
import uuid
import torch
from faster_whisper import WhisperModel

MODEL_SIZE = "small"

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
COMPUTE_TYPE = "float16" if DEVICE == "cuda" else "int8"

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

# Khởi tạo mô hình
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

    print(f"📥 Đã nhận file: {filepath} | Kích thước: {os.path.getsize(filepath)} bytes")
    return filepath

def transcribe(filepath: str, language: str = "vi") -> str:
    print(f"🔍 Đang xử lý file: {filepath} ({os.path.getsize(filepath)} bytes)")
    
    # Cấu hình tối ưu nhất cho Faster-Whisper
    segments, info = model.transcribe(
        filepath,
        language="vi",
        beam_size=1,                         # Giảm beam_size xuống 1 để tránh kẹt loop
        best_of=1,
        vad_filter=False,                    # Tắt VAD filter
        condition_on_previous_text=False,    # Tránh bỏ qua văn bản nếu khoảng lặng dài
        temperature=0.0                      # Giải thuật suy luận chính xác nhất
    )

    results = []
    for segment in segments:
        print(f"🗣️ Đoạn dịch [{segment.start:.1f}s -> {segment.end:.1f}s]: '{segment.text}'")
        results.append(segment.text)

    text = "".join(results).strip()
    print(f"✅ Kết quả cuối cùng: '{text}'")
    return text

    results = []
    for segment in segments:
        print(f"🗣️ [{segment.start:.2f}s -> {segment.end:.2f}s]: {segment.text}")
        results.append(segment.text)

    text = "".join(results).strip()
    return text