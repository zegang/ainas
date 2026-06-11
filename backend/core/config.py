import os
import logging
from pathlib import Path
from dotenv import load_dotenv

# File is at: ainas/backend/core/config.py
# Path(__file__).resolve().parent.parent is: ainas/backend
BACKEND_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BACKEND_DIR / ".env")

# Base directory for the AI engine and relative paths
BASE_DIR = os.getenv("AI_NAS_BACKEND_BASE_DIR")
if not BASE_DIR:
    BASE_DIR = str(BACKEND_DIR)
os.environ["AI_NAS_BACKEND_BASE_DIR"] = BASE_DIR

# Server Settings
NAS_HOST = os.getenv("NAS_HOST", "0.0.0.0")
NAS_PORT = int(os.getenv("NAS_PORT", "9026"))
NAS_ADVERTISE_ADDR = os.getenv("NAS_ADVERTISE_ADDR", NAS_HOST)

# Storage Settings
STORAGE_PATH = os.path.abspath(os.path.join(BASE_DIR, "../data"))
THUMBNAIL_DIR = os.path.join(STORAGE_PATH, ".thumbnails")
MODELS_DIR = os.path.join(BASE_DIR, "ai", "models")

# AI Settings
ENABLE_AI = os.getenv("ENABLE_AI", "false").lower() == "true"
AI_PROVIDER = os.getenv("AI_PROVIDER", "local").lower()
AI_MODEL = os.getenv("AI_MODEL", "services/ai/models/Qwen3-0.6B-Q8_0.gguf")
AI_API_URL = os.getenv("AI_API_URL", "https://api.openai.com/v1")
AI_API_KEY = os.getenv("AI_API_KEY", "")
AI_VISION_PROJECTOR = os.getenv("AI_VISION_PROJECTOR", "services/ai/models/mmproj-model-f16.gguf")
AI_GPU_LAYERS = int(os.getenv("AI_GPU_LAYERS", "32"))
DISK_USAGE_THRESHOLD_PCT = float(os.getenv("DISK_USAGE_THRESHOLD_PCT", "90.0"))

# Logging
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

# Create directories
os.makedirs(STORAGE_PATH, exist_ok=True)
os.makedirs(THUMBNAIL_DIR, exist_ok=True)
os.makedirs(MODELS_DIR, exist_ok=True)