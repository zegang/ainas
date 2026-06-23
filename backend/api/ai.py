import json
import logging
import uuid
import time
import asyncio
import os
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from backend.services.ai.ai_engine import AIEngine
from backend.services.monitoring.prometheus import AI_STREAM_TTFC
from backend.core import config
from backend.api.files import get_ai
from backend.services.huggingface_service import HuggingFaceService
from backend.db.database import db_manager, AiModelRecord, FeatureModelRecord

router = APIRouter(prefix="/api/ai", tags=["AI"])

# --- Schemas ---
class ChatRequest(BaseModel):
    text: str
    files: Optional[List[str]] = []
    request_id: Optional[str] = None

class DownloadModelRequest(BaseModel):
    repo_id: str
    filename: Optional[str] = None

class CheckModelRequest(BaseModel):
    repo_id: str
    filename: str | None = None

class DeleteModelRequest(BaseModel):
    name: str

class FunctionModelCreate(BaseModel):
    functionality: str
    model_name: str

class FunctionModelResponse(BaseModel):
    id: int
    functionality: str
    model_name: str
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

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

@router.post("/chat/stream")
async def ai_chat_stream(
    body: ChatRequest,
    request: Request,
    ai: AIEngine = Depends(get_ai)
):
    """Streaming chat endpoint for real-time responses."""
    logger = logging.getLogger(__name__)
    if not ai:
        async def disabled_gen():
            yield "AI Assistant is currently disabled."
        return StreamingResponse(disabled_gen(), media_type="text/plain")

    req_id = body.request_id or str(uuid.uuid4())
    ai.start_request(req_id)

    try:
        filenames = body.files or []
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
                async for chunk in ai.chat_stream(body.text, filenames=filenames, request_id=req_id):
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

@router.get("/models")
async def list_models():
    """Lists all model records from the database."""
    try:
        db = db_manager.SessionLocal()
        try:
            records = db.query(AiModelRecord).order_by(AiModelRecord.created_at.desc()).all()
            return {
                "models": [
                    {
                        "name": r.name,
                        "provider": r.provider,
                        "model_type": r.model_type,
                        "api_base": r.api_base,
                        "config": r.config,
                        "is_active": r.is_active,
                        "is_local": r.is_local,
                        "is_ready": r.is_ready,
                        "download_start_at": r.download_start_at.isoformat() if r.download_start_at else None,
                        "downloaded_at": r.downloaded_at.isoformat() if r.downloaded_at else None,
                        "all_model_files": (files := json.loads(r.all_model_files)) if r.all_model_files else None,
                        "current_model_files": (json.loads(r.current_model_files)) if r.current_model_files else None,
                        "total_size": r.total_size if r.total_size is not None else (
                            sum(files.values()) if isinstance(files, dict) else None
                        ),
                        "current_total_size": r.current_total_size,
                        "created_at": r.created_at.isoformat() if r.created_at else None,
                        "updated_at": r.updated_at.isoformat() if r.updated_at else None,
                    }
                    for r in records
                ]
            }
        finally:
            db.close()
    except Exception as e:
        logging.getLogger(__name__).error("Failed to list models: %s", e)
        raise HTTPException(status_code=500, detail="Failed to retrieve model list.")

@router.post("/models/check")
async def check_model_downloaded(body: CheckModelRequest):
    """Checks if a model is fully downloaded. Provide *filename* for a single file,
    or omit it to check all files listed in ``all_model_files`` (snapshot)."""
    try:
        hf_service = HuggingFaceService()
        downloaded = hf_service.is_model_downloaded(body.repo_id, body.filename)
        return {
            "repo_id": body.repo_id,
            "filename": body.filename,
            "downloaded": downloaded,
        }
    except Exception as e:
        logging.getLogger(__name__).error("Failed to check model status: %s", e)
        raise HTTPException(status_code=500, detail="Failed to verify model download status.")

@router.post("/models/download", status_code=202)
async def download_hf_model(request: DownloadModelRequest):
    """Queues a model download from Hugging Face Hub. Creates a DB record immediately
    and enqueues the download via the service's task queue."""
    hf_service = HuggingFaceService()
    model_name = request.repo_id
    model_type = "gguf" if request.filename else "snapshot"

    hf_service._ensure_record(model_name, "huggingface", model_type)
    hf_service._enqueue_download(model_name, request.repo_id, filename=request.filename, model_type=model_type)

    return {"message": f"Download queued for {model_name}", "name": model_name}

@router.delete("/models")
async def remove_model(body: DeleteModelRequest, request: Request):
    """Deletes a local model by its name (repo_id like 'org/modelname')."""
    try:
        hf_service = HuggingFaceService()
        hf_service.remove_model(body.name)

        es = getattr(request.app.state, "es", None)
        if es:
            repo_folder = hf_service._repo_folder(body.name)
            removed = await es.delete_files_by_prefix(repo_folder)
            if removed:
                logging.getLogger(__name__).info(
                    "Deleted %d ES document(s) for model %s", removed, body.name
                )

        return {"message": f"Successfully deleted {body.name}"}
    except Exception as e:
        logging.getLogger(__name__).error("Failed to delete model: %s", e)
        raise HTTPException(status_code=500, detail="Failed to delete model file.")

@router.post("/models/sync")
async def sync_models_from_cache():
    """Scan the HF cache directory and add any missing model records to the DB."""
    try:
        from backend.services.huggingface_service import HuggingFaceService
        svc = HuggingFaceService()
        result = svc.sync_db_from_cache()
        return {"message": "Sync complete", "added": result["added"], "already_present": result["already_present"], "errors": result["errors"]}
    except Exception as e:
        logging.getLogger(__name__).error("Failed to sync models from cache: %s", e)
        raise HTTPException(status_code=500, detail="Failed to sync models from cache.")

# --- AI Engine Status Endpoint ---

@router.get("/status")
async def ai_engine_status(request: Request):
    """Returns the current initialization status of the AI Engine."""
    status = getattr(request.app.state, "ai_status", None)
    if not status:
        return {"status": "disabled", "features": [], "models_available": 0}
    return {
        "status": status.status,
        "features": status.features,
        "feature_states": list(status.feature_states.values()),
        "models_available": status.models_available,
        "error": status.error,
        "elapsed": round(status.elapsed, 1),
    }


# --- Feature Registry Endpoints ---

@router.get("/features")
async def list_features(request: Request, ai: AIEngine = Depends(get_ai)):
    """Lists all registered AI features and their currently assigned models."""
    if ai:
        return {"features": ai.features.list_with_models()}
    status = getattr(request.app.state, "ai_status", None)
    if status and status.features:
        return {"features": status.features, "status": status.status}
    raise HTTPException(status_code=503, detail="AI Engine is still initializing or not enabled.")


class SetFeatureModelBody(BaseModel):
    model_name: str


@router.post("/features/{name}/model", status_code=202)
async def set_feature_model(name: str, body: SetFeatureModelBody, ai: AIEngine = Depends(get_ai)):
    """Set the model for a registered feature by name. Model loading runs in background."""
    logger = logging.getLogger(__name__)
    if not ai:
        raise HTTPException(status_code=503, detail="AI Engine is still initializing or not enabled.")
    try:
        logger.info("Setting model '%s' for feature '%s'", body.model_name, name)
        ai.features.set_feature_model_async(name, body.model_name)
        return {"message": f"Model '{body.model_name}' is being set for feature '{name}' in background."}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.error("Failed to set feature model: %s", e)
        raise HTTPException(status_code=500, detail="Failed to set feature model.")

# --- RAG Endpoints ---

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

@router.get("/rag/documents")
async def rag_documents(request: Request):
    """Lists indexed documents from the RAG/Elasticsearch backend."""
    es = getattr(request.app.state, "es", None)
    if not es:
        return {"documents": [], "total": 0}
    try:
        summary = await es.get_index_summary()
        docs = summary.get("files", [])
        return {"files": docs, "total": summary.get("total_chunks", 0)}
    except Exception as e:
        logging.getLogger(__name__).error("Failed to list RAG documents: %s", e)
        return {"documents": [], "total": 0, "error": str(e)}

@router.delete("/rag/documents")
async def rag_delete_document(path: str, request: Request):
    """Deletes a single indexed document by its path from the RAG/Elasticsearch backend."""
    es = getattr(request.app.state, "es", None)
    if not es:
        raise HTTPException(status_code=503, detail="Elasticsearch not available")
    if not path:
        raise HTTPException(status_code=400, detail="path parameter is required")
    try:
        deleted = await es.delete_file(path)
        return {"deleted": deleted, "message": f"Document '{path}' deleted."}
    except Exception as e:
        logging.getLogger(__name__).error("Failed to delete RAG document: %s", e)
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/rag")
async def rag_clear_index(request: Request):
    """Deletes all indexed documents from the RAG/Elasticsearch backend."""
    es = getattr(request.app.state, "es", None)
    if not es:
        raise HTTPException(status_code=503, detail="Elasticsearch not available")
    try:
        deleted = await es.clear_index()
        return {"deleted": deleted, "message": "RAG index cleared successfully."}
    except Exception as e:
        logging.getLogger(__name__).error("Failed to clear RAG index: %s", e)
        raise HTTPException(status_code=500, detail=str(e))