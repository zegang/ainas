import os
import logging
import uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from dotenv import load_dotenv
from prometheus_fastapi_instrumentator import Instrumentator

# Set base directory and environment variable before other internal imports
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
os.environ["AI_NAS_BACKEND_BASE_DIR"] = BASE_DIR

load_dotenv()

# Configure logging immediately after setting BASE_DIR and loading environment variables,
# and before any other modules that might use logging are imported.
log_format = "%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s"
log_dir = os.path.join(BASE_DIR, "../logs")
os.makedirs(log_dir, exist_ok=True)
log_file = os.path.join(log_dir, "backend.log")

# Determine logging level from environment variable
log_level_str = os.getenv("LOG_LEVEL", "DEBUG").upper()
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
from backend.ai.ai_engine import AIEngine
def configure_logging():
    """Configures global logging with file and stream handlers."""
    log_format = "%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s"
    log_dir = os.path.join(BASE_DIR, "../logs")
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, "backend.log")

    logging.basicConfig(
        level=logging.INFO,
        format=log_format,
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    nas_host = os.getenv("NAS_HOST", "0.0.0.0")
    nas_port = int(os.getenv("NAS_PORT", "9026"))
    advertise_addr = os.getenv("NAS_ADVERTISE_ADDR", nas_host)
    enable_ai = os.getenv("ENABLE_AI", "false").lower() == "true"
    
    discovery = NASDiscovery(host=advertise_addr, port=nas_port)

    startup_logger = logging.getLogger(__name__)
    startup_logger.info("AI-NAS starting... AI Features: %s", "Enabled" if enable_ai else "Disabled")
    await discovery.register()
    if enable_ai: # This is where AIEngine is instantiated
        app.state.ai = AIEngine()
    yield
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
    logger.info(f'AI NAS Backend Base Dir: {os.environ["AI_NAS_BACKEND_BASE_DIR"]}')
    
    host = os.getenv("NAS_HOST", "0.0.0.0")
    port = int(os.getenv("NAS_PORT", "9026"))
    uvicorn.run(app, host=host, port=port)