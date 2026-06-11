import os
import shutil
import logging
import uuid
import time
from typing import List, Optional
from fastapi import APIRouter, UploadFile, File, Depends, Response, HTTPException, BackgroundTasks
from fastapi import Request # Import Request
from fastapi.responses import JSONResponse, StreamingResponse, FileResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from backend.services.image_service import create_thumbnail
from backend.services.system_service import get_disk_usage, check_disk_and_alert
import asyncio
from backend.services.ai.ai_engine import AIEngine
from backend.services.monitoring.prometheus import AI_STREAM_TTFC
from backend.db.database import SessionLocal, FileRecord, TagRecord
from backend.core import config

logger = logging.getLogger(__name__)

# Dependency Injection for AI Engine
def get_ai(request: Request):
    app_ai = getattr(request.app.state, "ai", None)
    if not app_ai:
        logger.warning("AI Engine not enabled or initialized.")
        return None
    return app_ai
router = APIRouter()
def get_enable_ai():
    return config.ENABLE_AI

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# --- Schemas ---
class StatusResponse(BaseModel):
    message: str
    ai_enabled: bool

class RenameRequest(BaseModel):
    path: str
    new_name: str

class MoveRequest(BaseModel):
    path: str
    new_path: str

class CreateFolderRequest(BaseModel):
    path: str

class ChatRequest(BaseModel):
    text: str
    files: Optional[List[str]] = []
    request_id: Optional[str] = None

class DownloadModelRequest(BaseModel):
    repo_id: str
    filename: str

@router.get("/api/status", response_model=StatusResponse)
async def status(enabled: bool = Depends(get_enable_ai)):
    return {"message": "AI-NAS API is operational", "ai_enabled": enabled}

@router.get("/api/system/usage")
async def system_usage():
    """Returns current disk usage statistics and triggers logs if critical."""
    return check_disk_and_alert()

@router.get("/favicon.ico", include_in_schema=False)
async def favicon():
    # Return an empty response to silence 404s in the browser/logs
    return Response(status_code=204)

@router.get("/api/files/download")
async def download_file(path: str, thumbnail: bool = False):
    """
    Serves a file for download or preview.
    If thumbnail=True is passed and a thumbnail exists, serves the thumbnail for performance.
    """
    clean_path = path.strip().lstrip("/")
    full_path = os.path.abspath(os.path.join(config.STORAGE_PATH, clean_path))

    # Security: Ensure the path is within the storage root
    if not full_path.startswith(os.path.abspath(config.STORAGE_PATH)):
        raise HTTPException(status_code=403, detail="Access denied")

    if not os.path.exists(full_path) or os.path.isdir(full_path):
        raise HTTPException(status_code=404, detail="File not found")

    # Optimization: Use thumbnail if requested and available
    if thumbnail:
        thumb_path = os.path.abspath(os.path.join(config.THUMBNAIL_DIR, clean_path))
        if os.path.exists(thumb_path):
            return FileResponse(thumb_path)

    return FileResponse(full_path)

@router.get("/api/files")
async def list_files(path: str = "", db: Session = Depends(get_db)):
    clean_path = path.strip().lstrip("/")
    full_path = os.path.abspath(os.path.join(config.STORAGE_PATH, clean_path))
    
    if not os.path.exists(full_path):
        logger.warning("Path access attempt failed: %s does not exist", full_path)
        return {"items": [], "error": "Path does not exist"}
        
    items = os.listdir(full_path)
    
    results = []
    for item in items:
        item_abs_path = os.path.join(full_path, item)
        st = os.stat(item_abs_path)
        is_dir = os.path.isdir(item_abs_path)
        # Relative path for DB lookup
        item_rel_path = os.path.join(clean_path, item).replace("\\", "/")
        
        # Query DB for tags
        file_rec = db.query(FileRecord).filter(FileRecord.path == item_rel_path).first()
        tags = [t.name for t in file_rec.tags] if file_rec else []
        
        results.append({
            "name": item,
            "path": item_rel_path,
            "is_dir": is_dir,
            "size": st.st_size if not is_dir else 0,
            "updated_at": st.st_mtime,
            "created_at": st.st_ctime,
            "tags": tags
        })
        
    return {"items": results}

@router.post("/api/files/folder")
async def create_folder(request: CreateFolderRequest):
    """Create a new directory at the specified relative path."""
    # Sanitize path to prevent escaping STORAGE_PATH
    rel_path = request.path.lstrip("/")
    full_path = os.path.join(config.STORAGE_PATH, rel_path)
    
    if os.path.exists(full_path):
        raise HTTPException(status_code=400, detail="Path already exists")
    
    try:
        os.makedirs(full_path, exist_ok=True)
        return {"message": f"Folder created successfully at {rel_path}"}
    except Exception as e:
        logger.error("Folder creation failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/api/files")
async def delete_item(path: str, db: Session = Depends(get_db)):
    full_path = os.path.join(config.STORAGE_PATH, path)
    if not os.path.exists(full_path):
        raise HTTPException(status_code=404, detail="Item not found")
    
    if os.path.isdir(full_path):
        shutil.rmtree(full_path)
    else:
        os.remove(full_path)
        
    # Cleanup DB records for the file and any children if it was a directory
    db.query(FileRecord).filter(FileRecord.path == path).delete()
    db.query(FileRecord).filter(FileRecord.path.like(f"{path}/%")).delete()
    db.commit()
    return {"message": f"Successfully deleted {path}"}

@router.patch("/api/files/rename")
async def rename_item(request: RenameRequest, db: Session = Depends(get_db)):
    old_abs = os.path.join(config.STORAGE_PATH, request.path)
    if not os.path.exists(old_abs):
        raise HTTPException(status_code=404, detail="Item not found")
        
    parent = os.path.dirname(request.path)
    new_rel = os.path.join(parent, request.new_name).lstrip("/")
    new_abs = os.path.join(config.STORAGE_PATH, new_rel)
    
    is_dir = os.path.isdir(old_abs)
    os.rename(old_abs, new_abs)
    
    # Update DB path for the item itself
    record = db.query(FileRecord).filter(FileRecord.path == request.path).first()
    if record:
        record.path = new_rel

    # If it was a directory, update all children records
    if is_dir:
        prefix = f"{request.path}/"
        children = db.query(FileRecord).filter(FileRecord.path.like(f"{prefix}%")).all()
        for child in children:
            # Replace the old parent prefix with the new parent prefix
            child.path = new_rel + child.path[len(request.path):]
            
    db.commit()
    return {"new_path": new_rel}

@router.patch("/api/files/move")
async def move_item(request: MoveRequest, db: Session = Depends(get_db)):
    old_abs = os.path.join(config.STORAGE_PATH, request.path)
    new_abs = os.path.join(config.STORAGE_PATH, request.new_path)
    
    if not os.path.exists(old_abs):
        raise HTTPException(status_code=404, detail="Source item not found")
        
    is_dir = os.path.isdir(old_abs)
    shutil.move(old_abs, new_abs)
    
    record = db.query(FileRecord).filter(FileRecord.path == request.path).first()
    if record:
        record.path = request.new_path

    # If it was a directory, update all children records
    if is_dir:
        prefix = f"{request.path}/"
        children = db.query(FileRecord).filter(FileRecord.path.like(f"{prefix}%")).all()
        for child in children:
            # Replace the old path prefix with the new one
            child.path = request.new_path + child.path[len(request.path):]
            
    db.commit()
    return {"new_path": request.new_path}

def thumbnail_task(rel_path: str):
    """Background task wrapper to resolve paths and trigger thumbnail creation.
    Maintains the directory structure within the .thumbnails directory."""
    source = os.path.join(config.STORAGE_PATH, rel_path.lstrip("/"))
    destination = os.path.join(config.THUMBNAIL_DIR, rel_path.lstrip("/"))

    # Ensure the parent directory structure exists in the thumbnails folder
    os.makedirs(os.path.dirname(destination), exist_ok=True)

    # Only process files with image extensions
    if rel_path.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif')):
        try:
            create_thumbnail(source, destination)
        except Exception:
            # Errors are logged in the service
            pass

@router.post("/api/upload")
async def upload_file(
    background_tasks: BackgroundTasks,
    path: str = "", 
    file: UploadFile = File(...), 
    db: Session = Depends(get_db),
    ai: AIEngine = Depends(get_ai)
):
    logger.info("Received upload request for file: %s in path: %s", file.filename, path)
    
    # Resolve target directory and validate security
    clean_parent = path.strip().lstrip("/")
    
    # Sanitize the filename to prevent path traversal attacks
    safe_filename = os.path.basename(file.filename)
    
    file_rel_path = os.path.join(clean_parent, safe_filename).replace("\\", "/")
    file_path = os.path.abspath(os.path.join(config.STORAGE_PATH, file_rel_path))

    if not file_path.startswith(os.path.abspath(config.STORAGE_PATH)):
        raise HTTPException(status_code=403, detail="Invalid target path")

    # Ensure parent directory exists
    os.makedirs(os.path.dirname(file_path), exist_ok=True)

    content = await file.read()
    with open(file_path, "wb") as f:
        f.write(content)
    
    # Schedule thumbnail generation in the background
    background_tasks.add_task(thumbnail_task, file_rel_path)
    
    # Pass the relative path for AI tagging logic
    tags = ai.generate_tags(file_rel_path) if ai else []
    if ai:
        logger.info("AI generated tags for %s: %s", file_rel_path, tags)
    
    # Persist to Database
    file_rec = db.query(FileRecord).filter(FileRecord.path == file_rel_path).first()
    if not file_rec:
        file_rec = FileRecord(path=file_rel_path)
        db.add(file_rec)
        db.commit()
        db.refresh(file_rec)
    
    for tag_name in tags:
        db.add(TagRecord(name=tag_name, file_id=file_rec.id))
    db.commit()
    return {"filename": file.filename, "path": file_rel_path, "ai_tags": tags}

@router.post("/ai/chat")
async def ai_chat(request: ChatRequest, ai: AIEngine = Depends(get_ai)):
    """Standard chat endpoint for the AI Assistant."""
    if not ai:
        return {"text": "AI Assistant is currently disabled.", "is_user": False}

    request_id = request.request_id or str(uuid.uuid4())
    ai.start_request(request_id)
    try:
        # Using AIEngine to generate a response
        response = await ai.chat(request.text, filenames=request.files, request_id=request_id)
        return {"text": response, "is_user": False}
    except asyncio.CancelledError:
        logger.info(f"AI chat request {request_id} was cancelled by client.")
        raise HTTPException(status_code=400, detail="AI chat request cancelled.")
    except Exception as e:
        logger.error("AI Chat error: %s", e)
        raise HTTPException(status_code=500, detail="AI Assistant encountered an error.")
    finally:
        ai.end_request(request_id)

@router.get("/ai/chat/stream")
async def ai_chat_stream(
    text: str, 
    request: Request, # Inject Request to get client disconnect
    files: Optional[str] = None, 
    request_id: Optional[str] = None,
    ai: AIEngine = Depends(get_ai)
):
    """Streaming chat endpoint for real-time responses."""
    if not ai:
        async def disabled_gen():
            yield "AI Assistant is currently disabled."
        return StreamingResponse(disabled_gen(), media_type="text/plain")

    req_id = request_id or str(uuid.uuid4())
    ai.start_request(req_id)

    try:
        filenames = files.split(",") if files else []
        start_time = time.perf_counter()

        async def ttfc_wrapper():
            # Create a task to monitor client disconnect
            async def monitor_disconnect():
                try:
                    # Poll for disconnect since is_disconnected is a non-blocking check
                    while not await request.is_disconnected():
                        await asyncio.sleep(0.5)
                    logger.info(f"Client disconnected for request {req_id}.")
                    ai.cancel_request(req_id)
                except Exception as e:
                    logger.error(f"Error monitoring disconnect for {req_id}: {e}")

            disconnect_task = asyncio.create_task(monitor_disconnect())

            try:
                first = True
                async for chunk in ai.chat_stream(text, filenames=filenames, request_id=req_id):
                    if first:
                        AI_STREAM_TTFC.labels(type="chat").observe(time.perf_counter() - start_time)
                        first = False
                    yield chunk
            finally:
                disconnect_task.cancel()
                ai.end_request(req_id)

        return StreamingResponse(ttfc_wrapper(), media_type="text/plain")
    except asyncio.CancelledError:
        logger.info(f"AI chat stream request {req_id} was cancelled.")
        raise HTTPException(status_code=400, detail="AI chat stream request cancelled.")
    except Exception as e:
        logger.error("AI Stream error: %s", e)
        raise HTTPException(status_code=500, detail="AI Streaming failed.")

@router.post("/ai/chat/cancel/{request_id}")
async def cancel_ai_request(request_id: str, ai: AIEngine = Depends(get_ai)):
    """Cancels an ongoing AI chat or chat stream request."""
    if not ai:
        raise HTTPException(status_code=400, detail="AI Engine not enabled.")
    
    if ai.cancel_request(request_id):
        return {"message": f"Cancellation requested for AI request {request_id}"}
    else:
        raise HTTPException(status_code=404, detail=f"AI request {request_id} not found or already completed.")

@router.get("/api/models/local")
async def list_local_models():
    """Lists all GGUF models currently stored on the NAS."""
    try:
        if not os.path.exists(config.MODELS_DIR):
            return {"models": []}
        models = [f for f in os.listdir(config.MODELS_DIR) if f.endswith(".gguf")]
        return {"models": models}
    except Exception as e:
        logger.error("Failed to list local models: %s", e)
        raise HTTPException(status_code=500, detail="Failed to retrieve local model list.")

@router.get("/api/models/hf")
async def search_hf_models(query: str = "gguf"):
    """Searches Hugging Face Hub for models matching the query (filtered for GGUF)."""
    try:
        api = HfApi()
        models = api.list_models(search=query, tags="gguf", limit=15, sort="downloads", direction=-1)
        return [{"id": m.modelId, "downloads": getattr(m, 'downloads', 0)} for m in models]
    except Exception as e:
        logger.error("HF Hub search failed: %s", e)
        raise HTTPException(status_code=500, detail="Hugging Face Hub search failed.")

@router.post("/api/models/download")
async def download_hf_model(request: DownloadModelRequest):
    """Downloads a specific model file from Hugging Face Hub to the NAS storage."""
    try:
        logger.info("Downloading %s from %s...", request.filename, request.repo_id)
        path = hf_hub_download(
            repo_id=request.repo_id,
            filename=request.filename,
            local_dir=config.MODELS_DIR,
            local_dir_use_symlinks=False
        )
        return {"message": "Model downloaded successfully", "path": path}
    except Exception as e:
        logger.error("Model download failed: %s", e)
        raise HTTPException(status_code=500, detail=f"Download failed: {str(e)}")

@router.delete("/api/models/{filename}")
async def remove_local_model(filename: str):
    """Deletes a local model file to free up space."""
    file_path = os.path.join(config.MODELS_DIR, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Model file not found")
    
    os.remove(file_path)
    return {"message": f"Successfully deleted {filename}"}