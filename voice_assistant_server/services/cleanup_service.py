"""
Trước đây mỗi lần TTS/STT sinh ra 1 file trong outputs/ hoặc uploads/ bằng
UUID nhưng KHÔNG có cơ chế xoá -> file tồn đọng vô hạn, đầy ổ đĩa theo thời
gian. Module này chạy nền, định kỳ xoá các file cũ hơn FILE_RETENTION_HOURS.
"""
import asyncio
import logging
import os
import time

from config import settings

logger = logging.getLogger(__name__)

DIRS_TO_CLEAN = ["outputs", "uploads"]


def cleanup_old_files() -> int:
    """Xoá các file cũ hơn settings.FILE_RETENTION_HOURS trong các thư mục
    tạm. Trả về số file đã xoá."""
    cutoff = time.time() - settings.FILE_RETENTION_HOURS * 3600
    removed = 0

    for folder in DIRS_TO_CLEAN:
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            path = os.path.join(folder, name)
            try:
                if os.path.isfile(path) and os.path.getmtime(path) < cutoff:
                    os.remove(path)
                    removed += 1
            except OSError as e:
                logger.warning("Khong the xoa file %s: %s", path, e)

    if removed:
        logger.info("Cleanup: da xoa %d file audio tam qua han.", removed)
    return removed


async def cleanup_loop():
    """Vòng lặp chạy nền song song với server (khởi động trong lifespan của
    FastAPI), dọn file định kỳ mỗi CLEANUP_INTERVAL_MINUTES phút."""
    interval_seconds = settings.CLEANUP_INTERVAL_MINUTES * 60
    while True:
        try:
            cleanup_old_files()
        except Exception as e:
            logger.exception("Loi khi chay cleanup_old_files: %s", e)
        await asyncio.sleep(interval_seconds)
