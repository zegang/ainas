import os
import logging
import asyncio
import uvicorn
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from prometheus_fastapi_instrumentator import Instrumentator

from backend.core import config
from backend.net.discovery import NASDiscovery
from backend.api.api import router as api_router
from backend.services.ai.ai_engine import AIEngine
from backend.services.elasticsearch_service import ElasticsearchService

@asynccontextmanager
async def lifespan(app: FastAPI):
    discovery = NASDiscovery(host=config.AINAS_ADVERTISE_ADDR, port=config.AINAS_PORT)

    startup_logger = logging.getLogger(__name__)
    startup_logger.info("AI-NAS starting... AI Features: %s", "Enabled" if config.AINAS_ENABLE_AI else "Disabled")
    await discovery.register()

    if config.AINAS_ENABLE_AI:
        async def _load_ai_engine():
            try:
                # Move heavy model loading/downloading to a separate thread 
                # to keep the application responsive during startup.
                app.state.ai = await asyncio.to_thread(AIEngine)
                startup_logger.info("AI Engine background initialization (pre-warming) complete.")
            except Exception as e:
                startup_logger.error(f"AI Engine background initialization failed: {e}")

        # Start loading AI models without blocking the server startup
        asyncio.create_task(_load_ai_engine())
    
    # Initialize and verify Elasticsearch
    es_service = ElasticsearchService()
    await es_service.create_index()
    app.state.es = es_service

    yield
    if hasattr(app.state, "es"):
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
    # Initialize Prometheus instrumentation
    Instrumentator().instrument(app).expose(app)
    return app

# Initialize configuration explicitly with the backend directory
config.initialize(Path(__file__).resolve().parent)
logger = logging.getLogger(__name__)
app = create_app()

if __name__ == "__main__":
    uvicorn.run(app, host=config.AINAS_ADDR, port=config.AINAS_PORT)