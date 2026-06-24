import os
import sys
import logging
import asyncio
import uvicorn
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from prometheus_fastapi_instrumentator import Instrumentator

from backend.core import config
from backend.net.discovery import NASDiscovery
from backend.api.api import router as api_router
from backend.services.ai.ai_engine import AIEngine
from backend.services.ai.models.ai_status import AIStatus
from backend.services.elasticsearch_service import ElasticsearchService
from backend.db.database import run_migrations

# Initialize configuration explicitly with the backend directory
config.initialize(Path(__file__).resolve().parent)
logger = logging.getLogger(__name__)
logger.info("Configuration initialized. Backend directory: %s", config.AINAS_BACKEND_DIR)

@asynccontextmanager
async def lifespan(app: FastAPI):
    discovery = NASDiscovery(host=config.AINAS_ADVERTISE_ADDR, port=config.AINAS_PORT)

    logger.info("AI-NAS starting...")
    logger.info("AI: %s, AI RAG: %s", "Enabled" if config.AINAS_ENABLE_AI else "Disabled", "Enabled" if config.AINAS_ENABLE_AI_RAG else "Disabled")

    # Apply any pending database schema migrations before accepting requests
    await asyncio.to_thread(run_migrations)
    sys.stdout.flush()
    sys.stderr.flush()

    try:
        await asyncio.wait_for(discovery.register(), timeout=5)
    except asyncio.TimeoutError:
        logger.warning("mDNS service registration timed out (multicast may be unavailable)")

    if config.AINAS_ENABLE_AI:
        ai_status = AIStatus()
        app.state.ai_status = ai_status
        app.state.ai = None

        async def _load_ai_engine():
            try:
                # Move heavy model loading/downloading to a separate thread 
                # to keep the application responsive during startup.
                engine = await asyncio.to_thread(AIEngine, status=ai_status)
                app.state.ai = engine
                ai_status.status = "ready"
                logger.info("AI Engine background initialization (pre-warming) complete.")
            except Exception as e:
                ai_status.status = "error"
                ai_status.error = str(e)
                logger.error(f"AI Engine background initialization failed: {e}")

        # Start loading AI models without blocking the server startup
        logger.info("AI Engine background initialization starting...")
        asyncio.create_task(_load_ai_engine())
        logger.info("AI Engine background initialization started. Models will be available once loaded.")
    
    # Initialize and verify Elasticsearch (RAG backend)
    if config.AINAS_ENABLE_AI_RAG:
        logger.info("Initializing Elasticsearch service for RAG...")
        es_service = ElasticsearchService()
        await es_service.create_index()
        app.state.es = es_service
        logger.info("Elasticsearch service initialized and index verified.")
    else:
        logger.info("RAG disabled — skipping Elasticsearch initialization")

    yield
    if hasattr(app.state, "es") and config.AINAS_ENABLE_AI_RAG:
        await app.state.es.close()
    await discovery.unregister()

def create_app() -> FastAPI:
    """Factory function to initialize the FastAPI application."""
    app = FastAPI(
        lifespan=lifespan,
        title="AI-NAS API",
        description="Automated AI-tagging Network Attached Storage API with integrated machine learning metadata generation.",
        version="1.0.0",
        docs_url="/docs",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/doc", include_in_schema=False)
    async def redirect_to_docs():
        return RedirectResponse(url="/docs")

    app.include_router(api_router)

    # ── Serve Flutter Web build as static files ──────────────────────
    # In Docker: /app/frontend/web/  (copied by Dockerfile)
    # In dev:    frontend/build/web/ relative to repo root
    web_dir = os.environ.get(
        "AINAS_FRONTEND_WEB_DIR",
        str(config.AINAS_BACKEND_DIR.parent / "frontend" / "build" / "web"),
    )
    if os.path.isdir(web_dir):
        logger.info("Mounting Flutter web build from: %s", web_dir)
        app.mount("/", StaticFiles(directory=web_dir, html=True), name="frontend")
    else:
        logger.warning(
            "Web build directory not found at %s. "
            "Run `flutter build web --release` in the frontend/ directory.",
            web_dir,
        )

    # Initialize Prometheus instrumentation
    Instrumentator().instrument(app).expose(app)
    return app

app = create_app()

if __name__ == "__main__":
    uvicorn.run(app, host=config.AINAS_ADDR, port=config.AINAS_PORT)
