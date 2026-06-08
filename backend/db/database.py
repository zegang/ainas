from sqlalchemy import create_engine, Column, Integer, String, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship

SQLALCHEMY_DATABASE_URL = "sqlite:///./nas_metadata.db"

engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class FileRecord(Base):
    __tablename__ = "files"
    id = Column(Integer, primary_key=True, index=True)
    path = Column(String, unique=True, index=True)
    tags = relationship("TagRecord", back_populates="file", cascade="all, delete-orphan")

class TagRecord(Base):
    __tablename__ = "tags"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    file_id = Column(Integer, ForeignKey("files.id"))
    file = relationship("FileRecord", back_populates="tags")

Base.metadata.create_all(bind=engine)