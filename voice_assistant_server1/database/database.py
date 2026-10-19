from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# 1. Đường dẫn file database SQLite local
SQLALCHEMY_DATABASE_URL = "sqlite:///./app_voice.db"

# 2. Khởi tạo engine
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)
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