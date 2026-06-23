from sqlalchemy import create_engine, Column, Integer, String, BigInteger, DateTime, ForeignKey, Boolean, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime
import logging
import os
from pathlib import Path

logger = logging.getLogger(__name__)


def get_db_dir() -> Path:
    try:
        from platformdirs import user_data_dir
        db_dir = Path(user_data_dir("ainas", ensure_exists=True))
    except ImportError:
        import sys as _sys
        if _sys.platform == "win32":
            _base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
        elif _sys.platform == "darwin":
            _base = Path.home() / "Library" / "Application Support"
        else:
            _base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
        db_dir = _base / "ainas"
        db_dir.mkdir(parents=True, exist_ok=True)
    return db_dir


Base = declarative_base()


class DatabaseManager:
    def __init__(self, db_dir: Path | None = None):
        self.db_dir = db_dir or get_db_dir()
        self.url = f"sqlite:///{self.db_dir / 'nas_metadata.db'}"
        self.engine = create_engine(self.url, connect_args={"check_same_thread": False})
        self.SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=self.engine)


db_manager = DatabaseManager()


class FileRecord(Base):
    __tablename__ = "files"
    id = Column(Integer, primary_key=True, index=True)
    path = Column(String, unique=True, index=True)
    size = Column(BigInteger, nullable=True)
    created_at = Column(DateTime, nullable=True, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=True, default=datetime.utcnow, onupdate=datetime.utcnow)
    tags = relationship("TagRecord", back_populates="file", cascade="all, delete-orphan")


class TagRecord(Base):
    __tablename__ = "tags"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    file_id = Column(Integer, ForeignKey("files.id"))
    file = relationship("FileRecord", back_populates="tags")


class AiModelRecord(Base):
    __tablename__ = "ai_models"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    provider = Column(String, nullable=False)
    model_type = Column(String, nullable=False, default="chat")
    api_base = Column(String, nullable=True)
    config = Column(Text, nullable=True)
    is_active = Column(Boolean, default=False)
    is_local = Column(Boolean, default=False)
    is_ready = Column(Boolean, default=False)
    download_start_at = Column(DateTime, nullable=True)
    downloaded_at = Column(DateTime, nullable=True)
    all_model_files = Column(Text, nullable=True)
    current_model_files = Column(Text, nullable=True)
    total_size = Column(Integer, nullable=True)
    current_total_size = Column(Integer, nullable=True)
    created_at = Column(DateTime, nullable=True, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=True, default=datetime.utcnow, onupdate=datetime.utcnow)


class FeatureModelRecord(Base):
    __tablename__ = "function_models"
    id = Column(Integer, primary_key=True, index=True)
    functionality = Column(String, unique=True, index=True, nullable=False)
    model_name = Column(String, nullable=False)
    feature_title = Column(String, nullable=True)
    feature_description = Column(Text, nullable=True)
    created_at = Column(DateTime, nullable=True, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=True, default=datetime.utcnow, onupdate=datetime.utcnow)


def run_migrations() -> None:
    """
    Apply all pending Alembic migrations to bring the database schema up to date.

    This is called once at application startup (from main.py lifespan).  Using
    Alembic instead of raw ``Base.metadata.create_all`` means:

    * New columns / tables are added automatically without manual SQL.
    * A ``alembic_version`` table tracks which migrations have been applied, so
      each migration runs exactly once regardless of how many times the server
      restarts.
    * Adding a new migration file under ``db/migrations/versions/`` is all that
      is needed to ship a schema change — no downtime, no manual ALTER TABLE.

    SQLite note: Alembic is configured with ``render_as_batch=True`` in
    ``env.py``, which rewrites ALTER TABLE operations as a table-copy sequence
    because SQLite has limited ALTER support.
    """
    try:
        from alembic.config import Config
        from alembic import command

        # Resolve alembic.ini relative to this file so the command works from
        # any working directory (e.g. when started via uvicorn from the repo root)
        ini_path = os.path.join(os.path.dirname(__file__), "..", "alembic.ini")
        ini_path = os.path.abspath(ini_path)

        alembic_cfg = Config(ini_path)
        # Ensure script_location is absolute too
        migrations_dir = os.path.join(os.path.dirname(__file__), "migrations")
        alembic_cfg.set_main_option("script_location", os.path.abspath(migrations_dir))

        logger.info("Running database migrations…")
        command.upgrade(alembic_cfg, "head")
        logger.info("Database schema is up to date.")
    except Exception as exc:
        # Never crash the whole server just because of a migration error —
        # log loudly and fall back to create_all so development still works.
        logger.error("Alembic migration failed: %s — falling back to create_all", exc)
        Base.metadata.create_all(bind=db_manager.engine)