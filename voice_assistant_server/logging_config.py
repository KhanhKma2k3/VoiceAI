import logging

from config import settings


def setup_logging() -> None:
    """Gọi 1 lần lúc khởi động app (main.py). Thay thế toàn bộ print() rải
    rác trong services bằng logging có mức độ (INFO/WARNING/ERROR), có
    timestamp, dễ lọc và dễ đẩy ra file/log collector khi deploy thật."""
    logging.basicConfig(
        level=getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO),
        format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    # Thư viện bên thứ 3 quá ồn ở mức DEBUG/INFO, hạ bớt xuống WARNING.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("faster_whisper").setLevel(logging.WARNING)
