import os
import sys

# Cho phép import "config", "database", "routes"... như khi chạy từ thư mục
# voice_assistant_server/ (main.py cũng import kiểu tuyệt đối như vậy).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Test cần các biến môi trường bắt buộc (config.py fail-fast nếu thiếu).
os.environ.setdefault("GEMINI_API_KEY", "test-key-not-real")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test_app_voice.db")

import pytest


@pytest.fixture(scope="session", autouse=True)
def _cleanup_test_db():
    yield
    # Giải phóng mọi kết nối SQLite đang giữ tệp trước khi xóa (Windows khóa tệp đang mở).
    from database.database import engine
    engine.dispose()

    test_db = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "test_app_voice.db",
    )
    try:
        if os.path.exists(test_db):
            os.remove(test_db)
    except PermissionError:
        # Dự phòng: nếu vẫn bị khóa thì bỏ qua, tệp sẽ bị ghi đè ở lần chạy sau.
        pass
