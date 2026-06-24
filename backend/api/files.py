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
from backend.services.image_service import create_thumbnail, create_pdf_thumbnail, pdf_to_images
from backend.services.pdf_service import merge_to_pdf
from backend.services.system_service import check_disk_and_alert
from backend.services.ai.ai_engine import AIEngine
from backend.services.elasticsearch_service import ElasticsearchService
from backend.db.database import db_manager, FileRecord, TagRecord
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
    db = db_manager.SessionLocal()
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

class CopyRequest(BaseModel):
    paths: List[str]
    target_dir: str

class CreateFolderRequest(BaseModel):
    path: str

class DeleteRequest(BaseModel):
    path: str

class PdfToImagesRequest(BaseModel):
    path: str
    output_dir: str

class MergeToPdfRequest(BaseModel):
    file_paths: list[str]
    output_path: str

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
async def delete_item(body: DeleteRequest, request: Request, db: Session = Depends(get_db)):
    """Deletes a file or directory and cleans up associated database records
    (including tags via cascade) and Elasticsearch index entries."""
    logger = logging.getLogger(__name__)
    es: ElasticsearchService | None = getattr(request.app.state, "es", None)
    full_path = os.path.join(config.AINAS_DATA_PATH, body.path)
    if not os.path.exists(full_path):
        raise HTTPException(status_code=404, detail="Item not found")

    if os.path.isdir(full_path):
        shutil.rmtree(full_path)
        if es:
            removed = await es.delete_files_by_prefix(full_path)
            if removed:
                logger.info("Removed %d ES document(s) for directory %s", removed, body.path)
        records = db.query(FileRecord).filter(
            (FileRecord.path == body.path) | FileRecord.path.like(f"{body.path}/%")
        ).all()
        for rec in records:
            db.delete(rec)
    else:
        os.remove(full_path)
        if es:
            removed = await es.delete_file(full_path)
            if removed:
                logger.info("Removed %d ES document(s) for file %s", removed, body.path)
        for thumb_suffix in ["", ".jpg"]:
            thumb_path = os.path.join(config.AINAS_THUMBNAIL_DIR, body.path.lstrip("/") + thumb_suffix)
            if os.path.exists(thumb_path):
                try:
                    os.remove(thumb_path)
                    logger.info("Removed thumbnail: %s", thumb_path)
                except OSError as e:
                    logger.warning("Could not remove thumbnail %s: %s", thumb_path, e)

        rec = db.query(FileRecord).filter(FileRecord.path == body.path).first()
        if rec:
            db.delete(rec)

    db.commit()
    return {"message": f"Successfully deleted {body.path}"}

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

@router.post("/copy")
async def copy_items(body: CopyRequest, db: Session = Depends(get_db)):
    """Copies one or more files/directories into a target directory."""
    logger = logging.getLogger(__name__)
    target_abs = os.path.abspath(os.path.join(config.AINAS_DATA_PATH, body.target_dir.lstrip("/")))
    copied = []

    for src_path in body.paths:
        src_abs = os.path.abspath(os.path.join(config.AINAS_DATA_PATH, src_path.lstrip("/")))
        if not src_abs.startswith(os.path.abspath(config.AINAS_DATA_PATH)):
            logger.warning("Skipping path outside data dir: %s", src_path)
            continue
        if not os.path.exists(src_abs):
            logger.warning("Source not found: %s", src_path)
            continue

        name = os.path.basename(src_path.rstrip("/"))
        dst_abs = os.path.join(target_abs, name)

        if os.path.exists(dst_abs):
            logger.warning("Destination exists, skipping: %s", dst_abs)
            continue

        if os.path.isdir(src_abs):
            shutil.copytree(src_abs, dst_abs)
            for root, _, files in os.walk(dst_abs):
                for f in files:
                    fpath = os.path.join(root, f)
                    rel = os.path.relpath(fpath, config.AINAS_DATA_PATH).replace("\\", "/")
                    st = os.stat(fpath)
                    db.add(FileRecord(
                        path=rel,
                        size=st.st_size,
                        created_at=datetime.fromtimestamp(st.st_ctime),
                        updated_at=datetime.fromtimestamp(st.st_mtime),
                    ))
        else:
            os.makedirs(target_abs, exist_ok=True)
            shutil.copy2(src_abs, dst_abs)
            st = os.stat(dst_abs)
            rel = os.path.relpath(dst_abs, config.AINAS_DATA_PATH).replace("\\", "/")
            db.add(FileRecord(
                path=rel,
                size=st.st_size,
                created_at=datetime.fromtimestamp(st.st_ctime),
                updated_at=datetime.fromtimestamp(st.st_mtime),
            ))

        copied.append(src_path)

    db.commit()
    logger.info("Copied %d item(s) to %s", len(copied), body.target_dir)
    return {"copied": copied, "target_dir": body.target_dir}

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
        db = db_manager.SessionLocal()
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

            # 2. Document indexing into Elasticsearch (extract, chunk, embed, index)
            if es:
                embeddings = ai.embeddings if ai else None
                await es.index_file(
                    file_path=file_path, rel_path=file_path,
                    filename=safe_filename, tags=tags,
                    embeddings=embeddings,
                )
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
        db = db_manager.SessionLocal()
        try:
            embeddings = ai.embeddings if ai and config.AINAS_ENABLE_AI else None
            for root, _, files in os.walk(config.AINAS_DATA_PATH):
                for name in files:
                    if not name.lower().endswith(('.pdf', '.docx', '.txt', '.md', '.log')):
                        continue
                    file_path = os.path.join(root, name)
                    rel_path = os.path.relpath(file_path, config.AINAS_DATA_PATH).replace("\\", "/")
                    try:
                        file_rec = db.query(FileRecord).filter(FileRecord.path == rel_path).first()
                        tags = [t.name for t in file_rec.tags] if file_rec else []
                        await es.index_file(
                            file_path=file_path, rel_path=file_path,
                            filename=name, tags=tags,
                            embeddings=embeddings,
                        )
                    except Exception as e:
                        logger.error(f"Error re-indexing {rel_path}: {e}")
        finally: db.close()

@router.post("/reindex")
async def trigger_reindex(background_tasks: BackgroundTasks, request: Request, ai: AIEngine = Depends(get_ai)):
    """Triggers a full re-scan and index of the NAS storage."""
    es = getattr(request.app.state, "es", None)
    if not es: raise HTTPException(status_code=400, detail="Elasticsearch service not enabled.")
    background_tasks.add_task(run_reindex, ai, es)
    return {"message": "Re-indexing started in background."}


@router.post("/pdf-to-images")
async def pdf_to_images_endpoint(body: PdfToImagesRequest, request: Request):
    """Render every page of a PDF to PNG images in the specified output directory."""
    logger = logging.getLogger(__name__)
    source = os.path.join(config.AINAS_DATA_PATH, body.path.lstrip("/"))
    if not os.path.isfile(source):
        raise HTTPException(status_code=404, detail="PDF file not found")

    output_dir = os.path.join(config.AINAS_DATA_PATH, body.output_dir.lstrip("/"))
    os.makedirs(output_dir, exist_ok=True)

    try:
        images = pdf_to_images(source, output_dir)
        # Return paths relative to data dir so frontend can construct download URLs
        rel_base = body.output_dir.lstrip("/")
        for img in images:
            img["path"] = f"{rel_base}/{img['filename']}"
        return {"total_pages": len(images), "images": images}
    except (RuntimeError, OSError) as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/merge-to-pdf")
async def merge_to_pdf_endpoint(body: MergeToPdfRequest):
    """Merge multiple files (images and/or PDFs) into a single PDF."""
    logger = logging.getLogger(__name__)

    valid_paths = []
    for src in body.file_paths:
        full = os.path.abspath(os.path.join(config.AINAS_DATA_PATH, src.lstrip("/")))
        if not full.startswith(os.path.abspath(config.AINAS_DATA_PATH)):
            raise HTTPException(status_code=403, detail=f"Access denied: {src}")
        if not os.path.isfile(full):
            raise HTTPException(status_code=404, detail=f"File not found: {src}")
        valid_paths.append(full)

    output_full = os.path.abspath(os.path.join(config.AINAS_DATA_PATH, body.output_path.lstrip("/")))
    if not output_full.startswith(os.path.abspath(config.AINAS_DATA_PATH)):
        raise HTTPException(status_code=403, detail="Access denied: output path")

    try:
        merge_to_pdf(valid_paths, output_full)
        return {"pdf_path": body.output_path, "file_count": len(valid_paths)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))