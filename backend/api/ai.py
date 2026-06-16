import logging
import uuid
import time
import asyncio
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from backend.services.ai.ai_engine import AIEngine
from backend.services.monitoring.prometheus import AI_STREAM_TTFC
from backend.core import config
from backend.api.files import get_ai
from backend.services.huggingface_service import HuggingFaceService

router = APIRouter(prefix="/api/ai", tags=["AI"])

# --- Schemas ---
class ChatRequest(BaseModel):
    text: str
    files: Optional[List[str]] = []
    request_id: Optional[str] = None

class DownloadModelRequest(BaseModel):
    repo_id: str
    filename: str

class ModelSettingsUpdate(BaseModel):
    AINAS_AI_CHAT_MODEL: Optional[str] = None
    AINAS_AI_VISION_MODEL: Optional[str] = None
    AINAS_AI_IMAGE_GEN_MODEL: Optional[str] = None

# --- AI Chat Endpoints ---

@router.post("/chat")
async def ai_chat(request: ChatRequest, ai: AIEngine = Depends(get_ai)):
    """Standard chat endpoint for the AI Assistant."""
    logger = logging.getLogger(__name__)
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

@router.get("/chat/stream")
async def ai_chat_stream(
    text: str, 
    request: Request, # Inject Request to get client disconnect
    files: Optional[str] = None, 
    request_id: Optional[str] = None,
    ai: AIEngine = Depends(get_ai)
):
    """Streaming chat endpoint for real-time responses."""
    logger = logging.getLogger(__name__)
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

@router.post("/chat/cancel/{request_id}")
async def cancel_ai_request(request_id: str, ai: AIEngine = Depends(get_ai)):
    """Cancels an ongoing AI chat or chat stream request."""
    if not ai:
        raise HTTPException(status_code=400, detail="AI Engine not enabled.")
    
    if ai.cancel_request(request_id):
        return {"message": f"Cancellation requested for AI request {request_id}"}
    else:
        raise HTTPException(status_code=404, detail=f"AI request {request_id} not found or already completed.")

# --- AI Model Management Endpoints ---

@router.get("/models/local")
async def list_local_models():
    """Lists all GGUF models currently stored on the NAS."""
    try:
        hf_service = HuggingFaceService()
        models = hf_service.list_local_models()
        return {"models": models}
    except Exception as e:
        logging.getLogger(__name__).error("Failed to list local models: %s", e)
        raise HTTPException(status_code=500, detail="Failed to retrieve local model list.")

@router.get("/models/hf")
async def search_hf_models(query: str = "gguf"):
    """Searches Hugging Face Hub for models matching the query (filtered for GGUF)."""
    try:
        hf_service = HuggingFaceService()
        return hf_service.search_models(query)
    except Exception as e:
        logging.getLogger(__name__).error("HF Hub search failed: %s", e)
        raise HTTPException(status_code=500, detail="Hugging Face Hub search failed.")

@router.get("/rag")
async def rag_status(request: Request):
    """Returns details about the RAG/Elasticsearch backend."""
    es = getattr(request.app.state, "es", None)
    status = "disconnected"
    doc_count = 0
    
    if es:
        try:
            # Attempt to get document count as a proxy for usage/connectivity
            count_resp = await es.client.count(index=config.AINAS_ES_INDEX)
            status = "connected"
            doc_count = count_resp.get("count", 0)
        except Exception:
            status = "error"
            
    return {
        "status": status,
        "address": config.AINAS_ES_URL,
        "index": config.AINAS_ES_INDEX,
        "usage_docs": doc_count
    }

@router.get("/models/check")
async def check_model_downloaded(repo_id: str, filename: str):
    """Checks if a specific model file is already downloaded to the NAS."""
    try:
        hf_service = HuggingFaceService()
        downloaded = hf_service.is_model_downloaded(repo_id, filename)
        return {"repo_id": repo_id, "filename": filename, "downloaded": downloaded}
    except Exception as e:
        logging.getLogger(__name__).error("Failed to check model status: %s", e)
        raise HTTPException(status_code=500, detail="Failed to verify model download status.")

@router.post("/models/download")
async def download_hf_model(request: DownloadModelRequest):
    """Downloads a specific model file from Hugging Face Hub to the NAS storage."""
    try:
        hf_service = HuggingFaceService()
        path = hf_service.download_model(request.repo_id, request.filename)
        return {"message": "Model downloaded successfully", "path": path}
    except ValueError as e:
        # HuggingFaceService raises ValueError for RepositoryNotFoundError or RevisionNotFoundError
        raise HTTPException(status_code=404, detail=str(e))
    except (IOError, Exception) as e:
        # HuggingFaceService raises IOError for FileDownloadError
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/models/{filename}")
async def remove_local_model(filename: str):
    """Deletes a local model file to free up space."""
    try:
        hf_service = HuggingFaceService()
        hf_service.remove_local_model(filename)
        return {"message": f"Successfully deleted {filename}"}
    except Exception as e:
        logging.getLogger(__name__).error("Failed to delete model: %s", e)
        raise HTTPException(status_code=500, detail="Failed to delete model file.")

@router.get("/config/models")
async def get_model_config():
    """Returns the currently configured models for different AI tasks."""
    return {
        "chat_model": config.AINAS_AI_CHAT_MODEL,
        "vision_model": config.AINAS_AI_VISION_MODEL,
        "image_gen_model": config.AINAS_AI_IMAGE_GEN_MODEL,
        "embedding_model": config.AINAS_EMBEDDING_MODEL,
        "provider": getattr(config, "AINAS_AI_PROVIDER", "local"),
        "chat_context_size": getattr(config, "AINAS_AI_CHAT_CONTEXT_SIZE", 2048),
        "chat_temperature": getattr(config, "AINAS_AI_CHAT_TEMPERATURE", 0.7),
        "chat_max_tokens": getattr(config, "AINAS_AI_CHAT_MAX_TOKENS", 512),
        "vision_context_size": getattr(config, "AINAS_AI_VISION_CONTEXT_SIZE", 2048),
        "vision_temperature": getattr(config, "AINAS_AI_VISION_TEMPERATURE", 0.7),
        "embedding_context_size": getattr(config, "AINAS_EMBEDDING_CONTEXT_SIZE", 512),
        "image_gen_max_tokens": getattr(config, "AINAS_AI_IMAGE_GEN_MAX_TOKENS", 512),
    }

@router.post("/config/models")
async def update_model_config(settings: ModelSettingsUpdate):
    """Updates the active model configuration and persists it to config.yaml."""
    updates = {}
    if settings.AINAS_AI_CHAT_MODEL: updates["AINAS_AI_CHAT_MODEL"] = settings.AINAS_AI_CHAT_MODEL
    if settings.AINAS_AI_VISION_MODEL: updates["AINAS_AI_VISION_MODEL"] = settings.AINAS_AI_VISION_MODEL
    if settings.AINAS_AI_IMAGE_GEN_MODEL: updates["AINAS_AI_IMAGE_GEN_MODEL"] = settings.AINAS_AI_IMAGE_GEN_MODEL
    
    if not updates:
        raise HTTPException(status_code=400, detail="No valid settings provided for update.")
        
    config.save_config(updates)
    return {"message": "Configuration updated successfully", "current_settings": updates}