import os
import shutil
import logging
from typing import List, Optional
from fastapi import APIRouter, UploadFile, File, Depends, Response, HTTPException
from fastapi import Request # Import Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from backend.ai.ai_engine import AIEngine
from backend.db.database import SessionLocal, FileRecord, TagRecord

logger = logging.getLogger(__name__)

# Dependency Injection for AI Engine
def get_ai(request: Request):
    app_ai = getattr(request.app.state, "ai", None)
    if not app_ai:
        return None
    return app_ai
router = APIRouter()
def get_enable_ai():
    return os.getenv("ENABLE_AI", "false").lower() == "true"

# Dynamically calculate the project root (up two levels from backend/api/api.py)
BASE_DIR = os.getenv("AI_NAS_BACKEND_BASE_DIR")
STORAGE_PATH = os.path.join(BASE_DIR, "../data")
os.makedirs(STORAGE_PATH, exist_ok=True)

MODELS_DIR = os.path.join(BASE_DIR, "ai", "models")
os.makedirs(MODELS_DIR, exist_ok=True)

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

class DownloadModelRequest(BaseModel):
    repo_id: str
    filename: str

@router.get("/api/status")
async def status(enabled: bool = Depends(get_enable_ai)):
    return {"message": "AI-NAS API is operational", "ai_enabled": enabled}

@router.get("/favicon.ico", include_in_schema=False)
async def favicon():
    # Return an empty response to silence 404s in the browser/logs
    return Response(status_code=204)

@router.get("/files")
async def list_files(path: str = "", db: Session = Depends(get_db)):
    full_path = os.path.join(STORAGE_PATH, path)
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
        rel_path = os.path.join(path, item)
        
        # Query DB for tags
        file_rec = db.query(FileRecord).filter(FileRecord.path == rel_path).first()
        tags = [t.name for t in file_rec.tags] if file_rec else []
        
        results.append({
            "name": item,
            "is_dir": is_dir,
            "size": st.st_size if not is_dir else 0,
            "updated_at": st.st_mtime,
            "created_at": st.st_ctime,
            "tags": tags
        })
        
    return {"items": results}

@router.post("/files/folder")
async def create_folder(request: CreateFolderRequest):
    """Create a new directory at the specified relative path."""
    # Sanitize path to prevent escaping STORAGE_PATH
    rel_path = request.path.lstrip("/")
    full_path = os.path.join(STORAGE_PATH, rel_path)
    
    if os.path.exists(full_path):
        raise HTTPException(status_code=400, detail="Path already exists")
    
    try:
        os.makedirs(full_path, exist_ok=True)
        return {"message": f"Folder created successfully at {rel_path}"}
    except Exception as e:
        logger.error("Folder creation failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/files")
async def delete_item(path: str, db: Session = Depends(get_db)):
    full_path = os.path.join(STORAGE_PATH, path)
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

@router.patch("/files/rename")
async def rename_item(request: RenameRequest, db: Session = Depends(get_db)):
    old_abs = os.path.join(STORAGE_PATH, request.path)
    if not os.path.exists(old_abs):
        raise HTTPException(status_code=404, detail="Item not found")
        
    parent = os.path.dirname(request.path)
    new_rel = os.path.join(parent, request.new_name).lstrip("/")
    new_abs = os.path.join(STORAGE_PATH, new_rel)
    
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

@router.patch("/files/move")
async def move_item(request: MoveRequest, db: Session = Depends(get_db)):
    old_abs = os.path.join(STORAGE_PATH, request.path)
    new_abs = os.path.join(STORAGE_PATH, request.new_path)
    
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

@router.post("/upload")
async def upload_file(
    file: UploadFile = File(...), 
    db: Session = Depends(get_db),
    ai: AIEngine = Depends(get_ai)
):
    logger.info("Received upload request for file: %s", file.filename)
    content = await file.read()
    file_path = os.path.join(STORAGE_PATH, file.filename)
    
    with open(file_path, "wb") as f:
        f.write(content)
    
    # Pass the filename instead of bytes to leverage the vision tool logic
    tags = ai.generate_tags(file.filename) if ai else []
    if ai:
        logger.info("AI generated tags for %s: %s", file.filename, tags)
    
    # Persist to Database
    file_rec = db.query(FileRecord).filter(FileRecord.path == file.filename).first()
    if not file_rec:
        file_rec = FileRecord(path=file.filename)
        db.add(file_rec)
        db.commit()
        db.refresh(file_rec)
    
    # Add tags (avoid duplicates in a real scenario with a unique constraint or check)
    for tag_name in tags:
        db.add(TagRecord(name=tag_name, file_id=file_rec.id))
    db.commit()

    return {"filename": file.filename, "ai_tags": tags}

@router.post("/ai/chat")
async def ai_chat(request: ChatRequest, ai: AIEngine = Depends(get_ai)):
    """Standard chat endpoint for the AI Assistant."""
    if not ai:
        return {"text": "AI Assistant is currently disabled.", "is_user": False}
    
    try:
        # Using AIEngine to generate a response
        response = ai.chat(request.text, filenames=request.files)
        return {"text": response, "is_user": False}
    except Exception as e:
        logger.error("AI Chat error: %s", e)
        raise HTTPException(status_code=500, detail="AI Assistant encountered an error.")

@router.get("/ai/chat/stream")
async def ai_chat_stream(text: str, files: Optional[str] = None, ai: AIEngine = Depends(get_ai)):
    """Streaming chat endpoint for real-time responses."""
    if not ai:
        async def disabled_gen():
            yield "AI Assistant is currently disabled."
        return StreamingResponse(disabled_gen(), media_type="text/plain")

    try:
        filenames = files.split(",") if files else []
        return StreamingResponse(ai.chat_stream(text, filenames=filenames), media_type="text/plain")
    except Exception as e:
        logger.error("AI Stream error: %s", e)
        raise HTTPException(status_code=500, detail="AI Streaming failed.")

@router.get("/api/models/local")
async def list_local_models():
    """Lists all GGUF models currently stored on the NAS."""
    try:
        if not os.path.exists(MODELS_DIR):
            return {"models": []}
        models = [f for f in os.listdir(MODELS_DIR) if f.endswith(".gguf")]
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
            local_dir=MODELS_DIR,
            local_dir_use_symlinks=False
        )
        return {"message": "Model downloaded successfully", "path": path}
    except Exception as e:
        logger.error("Model download failed: %s", e)
        raise HTTPException(status_code=500, detail=f"Download failed: {str(e)}")

@router.delete("/api/models/{filename}")
async def remove_local_model(filename: str):
    """Deletes a local model file to free up space."""
    file_path = os.path.join(MODELS_DIR, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Model file not found")
    
    os.remove(file_path)
    return {"message": f"Successfully deleted {filename}"}