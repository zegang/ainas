from fastapi import APIRouter, Depends, Response, Request
from pydantic import BaseModel
from backend.core import config
from backend.api.files import router as files_router
from backend.api.ai import router as ai_router
from backend.services.system_service import check_disk_and_alert

router = APIRouter()
router.include_router(files_router)
router.include_router(ai_router)

def get_enable_ai():
    return config.AINAS_ENABLE_AI

# --- Schemas ---
class StatusResponse(BaseModel):
    message: str
    ai_enabled: bool
    ai_status: str

@router.get("/api/status", response_model=StatusResponse)
async def status(request: Request, enabled: bool = Depends(get_enable_ai)):
    ai_status = "disabled"
    if enabled:
        ai_status = "initializing"
        # The AI Engine is attached to the app state once background loading completes
        if hasattr(request.app.state, "ai"):
            ai_status = "ready"
    return {"message": "AI-NAS API is operational", "ai_enabled": enabled, "ai_status": ai_status}

@router.get("/api/system/usage")
async def system_usage():
    """Returns current disk usage statistics and triggers logs if critical."""
    return check_disk_and_alert()

@router.get("/favicon.ico", include_in_schema=False)
async def favicon():
    # Return an empty response to silence 404s in the browser/logs
    return Response(status_code=204)