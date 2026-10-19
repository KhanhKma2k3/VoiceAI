from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

from config import settings

# 1. Đường dẫn CSDL đọc từ config (mặc định SQLite cho dev, có thể trỏ sang
#    Postgres/MySQL qua biến môi trường DATABASE_URL khi lên production).
SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

# connect_args chỉ cần thiết với SQLite (không cần với Postgres/MySQL).
connect_args = {"check_same_thread": False} if SQLALCHEMY_DATABASE_URL.startswith("sqlite") else {}

# 2. Khởi tạo engine
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 3. Dòng này tạo ra đối tượng 'Base' mà main.py đang tìm
Base = declarative_base()


# 4. Dependency cấp session cho API
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def run_light_migrations(engine_) -> None:
    """Base.metadata.create_all() chỉ tạo bảng MỚI, không thêm cột vào bảng
    đã tồn tại. Hàm này bổ sung các cột mới của bảng `users` vào DB cũ (đã có
    dữ liệu) để không phải xóa app_voice.db. An toàn khi chạy nhiều lần."""
    from sqlalchemy import inspect, text

    inspector = inspect(engine_)
    if "users" not in inspector.get_table_names():
        return
    existing = {c["name"] for c in inspector.get_columns("users")}
    # SQLite chấp nhận mọi tên kiểu; Postgres/MySQL thì không có "DATETIME" chuẩn
    # (Postgres dùng TIMESTAMP) nên chọn theo dialect để migration chạy được ở cả hai.
    dt_type = "DATETIME" if engine_.dialect.name == "sqlite" else "TIMESTAMP"
    new_columns = {
        "email": "VARCHAR(255)",
        "display_name": "VARCHAR(100)",
        "google_id": "VARCHAR(64)",
        "reset_code_hash": "VARCHAR",
        "reset_code_expires": dt_type,
        "reset_attempts": "INTEGER NOT NULL DEFAULT 0",
    }
    with engine_.begin() as conn:
        for name, ddl in new_columns.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE users ADD COLUMN {name} {ddl}"))
        # Unique index cho email/google_id (cho phép nhiều NULL).
        conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_email_unique ON users (email)"))
        conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_google_id_unique ON users (google_id)"))
