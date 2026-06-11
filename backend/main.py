import os
import logging
import uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from prometheus_fastapi_instrumentator import Instrumentator

from backend.core import config

# Configure logging immediately after setting BASE_DIR and loading environment variables,
# and before any other modules that might use logging are imported.
log_format = "%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s"
log_dir = os.path.join(config.BASE_DIR, "../logs")
os.makedirs(log_dir, exist_ok=True)
log_file = os.path.join(log_dir, "backend.log")

# Determine logging level from environment variable
log_level_str = config.LOG_LEVEL
log_level = logging.INFO # Default
if log_level_str == "DEBUG":
    log_level = logging.DEBUG
elif log_level_str == "WARNING":
    log_level = logging.WARNING
elif log_level_str == "ERROR":
    log_level = logging.ERROR
elif log_level_str == "CRITICAL":
    log_level = logging.CRITICAL

logging.basicConfig(
    level=log_level,
    format=log_format,
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__) # Get logger for main module after basicConfig

from backend.net.discovery import NASDiscovery
from backend.api.api import router as api_router
from backend.services.ai.ai_engine import AIEngine
from backend.services.elasticsearch_service import ElasticsearchService

@asynccontextmanager
async def lifespan(app: FastAPI):
    discovery = NASDiscovery(host=config.NAS_ADVERTISE_ADDR, port=config.NAS_PORT)

    startup_logger = logging.getLogger(__name__)
    startup_logger.info("AI-NAS starting... AI Features: %s", "Enabled" if config.ENABLE_AI else "Disabled")
    await discovery.register()
    if config.ENABLE_AI: # This is where AIEngine is instantiated
        app.state.ai = AIEngine()
    
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

app = create_app()

if __name__ == "__main__":
    logger.info(f'AI NAS Backend Base Dir: {config.BASE_DIR}')
    uvicorn.run(app, host=config.NAS_HOST, port=config.NAS_PORT)