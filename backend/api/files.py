import asyncio
import os
import shutil
import logging
from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, BackgroundTasks, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session
from backend.services.image_service import create_thumbnail, create_pdf_thumbnail
from backend.services.system_service import check_disk_and_alert
from backend.services.document_service import extract_text
from backend.services.ai.ai_engine import AIEngine
from backend.services.elasticsearch_service import ElasticsearchService
from backend.db.database import SessionLocal, FileRecord, TagRecord
from backend.core import config

router = APIRouter(prefix="/api/files", tags=["Files"])

# Global semaphore to cap concurrent post-upload tasks (AI tagging, indexing, thumbnail)
_task_semaphore: Optional[asyncio.Semaphore] = None

def _get_task_semaphore() -> asyncio.Semaphore:
    global _task_semaphore
    if _task_semaphore is None:
        _task_semaphore = asyncio.Semaphore(config.AINAS_MAX_CONCURRENT_TASKS)
    return _task_semaphore

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Dependency Injection for AI Engine
def get_ai(request: Request):
    app_ai = getattr(request.app.state, "ai", None)
    if not app_ai:
        logging.getLogger(__name__).warning("AI Engine not enabled or initialized.")
        return None
    return app_ai

# --- Schemas ---
class RenameRequest(BaseModel):
    path: str
    new_name: str

class MoveRequest(BaseModel):
    path: str
    new_path: str

class CreateFolderRequest(BaseModel):
    path: str

# --- Endpoints ---

@router.get("/download")
async def download_file(path: str, thumbnail: bool = False):
    """Serves a file for download or preview, with optional thumbnail optimization."""
    clean_path = path.strip().lstrip("/")
    full_path = os.path.abspath(os.path.join(config.AINAS_DATA_PATH, clean_path))

    if not full_path.startswith(os.path.abspath(config.AINAS_DATA_PATH)):
        raise HTTPException(status_code=403, detail="Access denied")

    if not os.path.exists(full_path) or os.path.isdir(full_path):
        raise HTTPException(status_code=404, detail="File not found")

    if thumbnail:
        thumb_path = os.path.abspath(os.path.join(config.AINAS_THUMBNAIL_DIR, clean_path))
        # PDF thumbnails are stored with an extra .jpg extension
        pdf_thumb_path = thumb_path + ".jpg"
        if os.path.exists(pdf_thumb_path):
            return FileResponse(pdf_thumb_path)
        if os.path.exists(thumb_path):
            return FileResponse(thumb_path)

    return FileResponse(full_path)

@router.get("/index-status")
async def get_file_index_status(path: str, request: Request):
    """Checks if a specific file path is indexed in Elasticsearch."""
    es = getattr(request.app.state, "es", None)
    if not es:
        raise HTTPException(status_code=400, detail="Elasticsearch service not enabled.")
    indexed = await es.check_file_exists(path)
    return {"path": path, "indexed": indexed}

@router.get("")
async def list_files(path: str = "", db: Session = Depends(get_db)):
    """Lists files and directories at the given path with associated metadata and tags."""
    clean_path = path.strip().lstrip("/")
    full_path = os.path.abspath(os.path.join(config.AINAS_DATA_PATH, clean_path))
    logger = logging.getLogger(__name__)
    logger.info("Listing files in %s", full_path)
    
    if not os.path.exists(full_path):
        return {"items": [], "error": "Path does not exist"}
        
    results = []
    for item in os.listdir(full_path):
        item_abs_path = os.path.join(full_path, item)
        st = os.stat(item_abs_path)
        is_dir = os.path.isdir(item_abs_path)
        item_rel_path = os.path.join(clean_path, item).replace("\\", "/")
        
        file_rec = db.query(FileRecord).filter(FileRecord.path == item_rel_path).first()
        tags = [t.name for t in file_rec.tags] if file_rec else []
        
        results.append({
            "name": item, "path": item_rel_path, "is_dir": is_dir,
            "size": st.st_size if not is_dir else 0,
            "updated_at": st.st_mtime, "created_at": st.st_ctime,
            "tags": tags
        })
    return {"items": results}

@router.post("/folder")
async def create_folder(request: CreateFolderRequest):
    """Creates a new directory at the specified path."""
    full_path = os.path.join(config.AINAS_DATA_PATH, request.path.lstrip("/"))
    if os.path.exists(full_path):
        raise HTTPException(status_code=400, detail="Path already exists")
    try:
        os.makedirs(full_path, exist_ok=True)
        return {"message": "Folder created successfully"}
    except Exception as e:
        logging.getLogger(__name__).error("Folder creation failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("")
async def delete_item(path: str, db: Session = Depends(get_db)):
    """Deletes a file or directory and cleans up associated database records (including tags via cascade)."""
    logger = logging.getLogger(__name__)
    full_path = os.path.join(config.AINAS_DATA_PATH, path)
    if not os.path.exists(full_path):
        raise HTTPException(status_code=404, detail="Item not found")

    if os.path.isdir(full_path):
        shutil.rmtree(full_path)
        # Load all child FileRecords (and the dir itself if recorded) and delete via ORM
        # so the cascade="all, delete-orphan" on TagRecord fires correctly.
        records = db.query(FileRecord).filter(
            (FileRecord.path == path) | FileRecord.path.like(f"{path}/%")
        ).all()
        for rec in records:
            db.delete(rec)
    else:
        os.remove(full_path)
        # Also remove thumbnail if it exists (image or PDF)
        for thumb_suffix in ["", ".jpg"]:
            thumb_path = os.path.join(config.AINAS_THUMBNAIL_DIR, path.lstrip("/") + thumb_suffix)
            if os.path.exists(thumb_path):
                try:
                    os.remove(thumb_path)
                    logger.info("Removed thumbnail: %s", thumb_path)
                except OSError as e:
                    logger.warning("Could not remove thumbnail %s: %s", thumb_path, e)

        rec = db.query(FileRecord).filter(FileRecord.path == path).first()
        if rec:
            db.delete(rec)

    db.commit()
    return {"message": f"Successfully deleted {path}"}

@router.patch("/rename")
async def rename_item(request: RenameRequest, db: Session = Depends(get_db)):
    """Renames an item and updates its path in the database."""
    old_abs = os.path.join(config.AINAS_DATA_PATH, request.path)
    if not os.path.exists(old_abs):
        raise HTTPException(status_code=404, detail="Item not found")
        
    new_rel = os.path.join(os.path.dirname(request.path), request.new_name).lstrip("/")
    new_abs = os.path.join(config.AINAS_DATA_PATH, new_rel)
    
    is_dir = os.path.isdir(old_abs)
    os.rename(old_abs, new_abs)
    
    record = db.query(FileRecord).filter(FileRecord.path == request.path).first()
    if record: record.path = new_rel
    if is_dir:
        children = db.query(FileRecord).filter(FileRecord.path.like(f"{request.path}/%")).all()
        for child in children:
            child.path = new_rel + child.path[len(request.path):]
            
    db.commit()
    return {"new_path": new_rel}

@router.patch("/move")
async def move_item(request: MoveRequest, db: Session = Depends(get_db)):
    """Moves an item to a new location."""
    old_abs = os.path.join(config.AINAS_DATA_PATH, request.path)
    new_abs = os.path.join(config.AINAS_DATA_PATH, request.new_path)
    
    if not os.path.exists(old_abs):
        raise HTTPException(status_code=404, detail="Source item not found")
        
    is_dir = os.path.isdir(old_abs)
    shutil.move(old_abs, new_abs)
    
    record = db.query(FileRecord).filter(FileRecord.path == request.path).first()
    if record: record.path = request.new_path
    if is_dir:
        children = db.query(FileRecord).filter(FileRecord.path.like(f"{request.path}/%")).all()
        for child in children:
            child.path = request.new_path + child.path[len(request.path):]
            
    db.commit()
    return {"new_path": request.new_path}

@router.post("/upload")
async def upload_file(background_tasks: BackgroundTasks, request: Request, path: str = "",
                      file: UploadFile = File(...), db: Session = Depends(get_db),
                      ai: Optional[AIEngine] = Depends(get_ai)):
    """Handles file uploads, triggers thumbnail generation, AI tagging, and indexing."""
    logger = logging.getLogger(__name__)
    safe_filename = os.path.basename(file.filename)
    file_rel_path = os.path.join(path.strip().lstrip("/"), safe_filename).replace("\\", "/")
    file_path = os.path.abspath(os.path.join(config.AINAS_DATA_PATH, file_rel_path))

    if not file_path.startswith(os.path.abspath(config.AINAS_DATA_PATH)):
        raise HTTPException(status_code=403, detail="Invalid target path")

    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    content = await file.read()
    with open(file_path, "wb") as f: f.write(content)

    # Stat the file immediately after writing for accurate metadata
    st = os.stat(file_path)
    now = datetime.utcnow()

    # Upsert the FileRecord with full metadata so the file is visible in lists right away
    file_rec = db.query(FileRecord).filter(FileRecord.path == file_rel_path).first()
    if not file_rec:
        file_rec = FileRecord(
            path=file_rel_path,
            size=st.st_size,
            created_at=datetime.fromtimestamp(st.st_ctime),
            updated_at=datetime.fromtimestamp(st.st_mtime),
        )
        db.add(file_rec)
    else:
        file_rec.size = st.st_size
        file_rec.updated_at = now
    db.commit()
    db.refresh(file_rec)

    # Schedule heavy processing tasks in the background
    background_tasks.add_task(thumbnail_task, file_rel_path)
    
    es = getattr(request.app.state, "es", None)
    background_tasks.add_task(process_upload_task, file_rel_path, file_path, safe_filename, ai, es)

    return {"filename": file.filename, "path": file_rel_path, "status": "processing"}

async def process_upload_task(file_rel_path: str, file_path: str,
                              safe_filename: str, ai: Optional[AIEngine],
                              es: Optional[ElasticsearchService]):
    """Background task to handle AI tagging, text extraction, embedding generation, and indexing."""
    logger = logging.getLogger(__name__)
    sem = _get_task_semaphore()
    async with sem:
        db = SessionLocal()
        try:
            # 1. AI Tagging (Images only) — run in thread pool to avoid blocking the event loop
            is_image = safe_filename.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'))
            tags = await asyncio.to_thread(ai.generate_tags, file_rel_path) if ai and is_image else []
            
            if tags:
                logger.info("AI generated tags on %s: %s", file_rel_path, ",".join(tags))
                file_rec = db.query(FileRecord).filter(FileRecord.path == file_rel_path).first()
                if file_rec:
                    for tag_name in tags:
                        if not db.query(TagRecord).filter(TagRecord.file_id == file_rec.id, TagRecord.name == tag_name).first():
                            db.add(TagRecord(name=tag_name, file_id=file_rec.id))
                    db.commit()

            # 2. Text extraction and Elasticsearch Indexing
            if es:
                is_doc = safe_filename.lower().endswith(('.pdf', '.docx', '.txt', '.md', '.log'))
                file_content = await asyncio.to_thread(extract_text, file_path)
                if file_content and (is_doc or is_image):
                    st = os.stat(file_path)
                    created_at = datetime.fromtimestamp(st.st_ctime).isoformat()
                    updated_at = datetime.fromtimestamp(st.st_mtime).isoformat()

                    max_retries = 3
                    initial_delay = 2
                    current_delay = initial_delay
                    file_embedding = await ai.embeddings.aembed_query(file_content) if ai else None
                    for attempt in range(max_retries):
                        try:
                            logger.info("Attempting Elasticsearch indexing for %s (Attempt %d/%d)", file_rel_path, attempt + 1, max_retries)
                            await es.index_file(
                                filename=safe_filename, path=file_rel_path,
                                tags=tags, content=file_content,
                                embedding=file_embedding,
                                created_at=created_at, updated_at=updated_at
                            )
                            logger.info("Elasticsearch successfully indexed file: %s, %s", safe_filename, file_rel_path)
                            break
                        except Exception as e:
                            logger.warning(f"Elasticsearch indexing failed for {file_rel_path} (Attempt {attempt + 1}/{max_retries}): {e}")
                            if attempt < max_retries - 1:
                                await asyncio.sleep(current_delay)
                                current_delay *= 2
                            else:
                                logger.error(f"Elasticsearch indexing failed permanently for {file_rel_path} after {max_retries} attempts.")
        except Exception as e:
            logger.error(f"Error in background processing for {file_rel_path}: {e}")
        finally:
            db.close()

def thumbnail_task(rel_path: str):
    """Background task to generate thumbnails for images and PDFs."""
    source = os.path.join(config.AINAS_DATA_PATH, rel_path.lstrip("/"))
    destination = os.path.join(config.AINAS_THUMBNAIL_DIR, rel_path.lstrip("/"))
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    lower = rel_path.lower()
    if lower.endswith(('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif')):
        try: create_thumbnail(source, destination)
        except Exception: pass
    elif lower.endswith('.pdf'):
        # PDF thumbnails are saved as <rel_path>.jpg next to the original path in thumbnail dir
        try: create_pdf_thumbnail(source, destination)
        except Exception: pass

async def run_reindex(ai: Optional[AIEngine], es: ElasticsearchService):
    """Walks the filesystem and re-indexes supported documents into Elasticsearch."""
    logger = logging.getLogger(__name__)
    sem = _get_task_semaphore()
    async with sem:
        db = SessionLocal()
        try:
            for root, _, files in os.walk(config.AINAS_DATA_PATH):
                for name in files:
                    if name.lower().endswith(('.pdf', '.docx', '.txt', '.md', '.log')):
                        file_path = os.path.join(root, name)
                        rel_path = os.path.relpath(file_path, config.AINAS_DATA_PATH).replace("\\", "/")
                        try:
                            content = await asyncio.to_thread(extract_text, file_path)
                            if not content: continue
                            file_rec = db.query(FileRecord).filter(FileRecord.path == rel_path).first()
                            tags = [t.name for t in file_rec.tags] if file_rec else []
                            file_embedding = await ai.embeddings.aembed_query(content) if ai and config.AINAS_ENABLE_AI else None
                            await es.index_file(filename=name, path=rel_path, tags=tags, content=content, embedding=file_embedding)
                        except Exception as e: logger.error(f"Error re-indexing {rel_path}: {e}")
        finally: db.close()

@router.post("/reindex")
async def trigger_reindex(background_tasks: BackgroundTasks, request: Request, ai: AIEngine = Depends(get_ai)):
    """Triggers a full re-scan and index of the NAS storage."""
    es = getattr(request.app.state, "es", None)
    if not es: raise HTTPException(status_code=400, detail="Elasticsearch service not enabled.")
    background_tasks.add_task(run_reindex, ai, es)
    return {"message": "Re-indexing started in background."}