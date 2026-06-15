import logging
import os
import yaml
from pathlib import Path
from dotenv import load_dotenv

class AppConfig:
    """Configuration class that loads settings from YAML, Environment variables, or defaults."""
    
    def __init__(self, backend_dir: Path, config_file: str = "config.yaml"):
        self._init_logs = []
        self.AINAS_BACKEND_DIR = backend_dir
        load_dotenv(self.AINAS_BACKEND_DIR / ".env")

        # Load configuration from YAML file if it exists
        self.AINAS_CONFIG_FILE = self.AINAS_BACKEND_DIR / config_file
        self._init_logs.append(("info", f"Loading configuration from {self.AINAS_CONFIG_FILE}"))
        self.file_config = {}
        if self.AINAS_CONFIG_FILE.exists():
            try:
                with open(self.AINAS_CONFIG_FILE, "r") as f:
                    self.file_config = yaml.safe_load(f) or {}
            except Exception as e:
                self._init_logs.append(("warning", f"Could not parse {self.AINAS_CONFIG_FILE}: {e}"))

        # Storage directory for the AI engine and relative paths
        self.AINAS_STORAGE_PATH = self.get_setting("AINAS_STORAGE_PATH")
        if not self.AINAS_STORAGE_PATH:
            self.AINAS_STORAGE_PATH = str(self.AINAS_BACKEND_DIR)
        if not os.path.isabs(self.AINAS_STORAGE_PATH):
            self.AINAS_STORAGE_PATH = os.path.abspath(os.path.join(self.AINAS_BACKEND_DIR, self.AINAS_STORAGE_PATH))
        self._init_logs.append(("info", f"AI-NAS Storage Dir: {self.AINAS_STORAGE_PATH}"))

        # Server Settings
        self.AINAS_ADDR = self.get_setting("AINAS_ADDR", "0.0.0.0")
        self.AINAS_PORT = int(self.get_setting("AINAS_PORT", "9026"))
        self.AINAS_ADVERTISE_ADDR = self.get_setting("AINAS_ADVERTISE_ADDR", self.AINAS_ADDR)

        # Storage Settings
        self.AINAS_DATA_PATH = os.path.abspath(os.path.join(self.AINAS_STORAGE_PATH, "nasdata"))
        self.AINAS_METADATA_DIR = os.path.abspath(os.path.join(self.AINAS_STORAGE_PATH, "nasmetadata"))
        self.AINAS_THUMBNAIL_DIR = os.path.join(self.AINAS_METADATA_DIR, "thumbnail")

        # AI Settings
        self.AINAS_ENABLE_AI = str(self.get_setting("AINAS_ENABLE_AI", "false")).lower() == "true"
        self.AINAS_AI_SVC_DIR = os.path.join(self.AINAS_BACKEND_DIR, "services", "ai")
        self.AINAS_AI_MODELS_DIR = os.path.join(self.AINAS_AI_SVC_DIR, "models")
        self.AINAS_HF_API_TOKEN = self.get_setting("AINAS_HF_API_TOKEN", "")
        self.AINAS_HF_CACHE_DIR = self.get_setting("AINAS_HF_CACHE_DIR", os.path.join(self.AINAS_AI_MODELS_DIR, "hfcache"))
        
        # Task-specific Model Settings
        self.AINAS_AI_CHAT_MODEL = self.get_setting("AINAS_AI_CHAT_MODEL", "services/ai/models/Qwen3-0.6B-Q8_0.gguf")
        self.AINAS_AI_VISION_MODEL = self.get_setting("AINAS_AI_VISION_MODEL", "Salesforce/blip-image-captioning-base")
        self.AINAS_AI_IMAGE_GEN_MODEL = self.get_setting("AINAS_AI_IMAGE_GEN_MODEL", "dall-e-3")
        self.AINAS_EMBEDDING_MODEL = self.get_setting("AINAS_EMBEDDING_MODEL", "sentence-transformers/all-mpnet-base-v2")

        self.AINAS_AI_API_URL = self.get_setting("AINAS_AI_API_URL", "https://api.openai.com/v1")
        self.AINAS_AI_API_KEY = self.get_setting("AINAS_AI_API_KEY", "")
        self.AINAS_AI_VISION_PROJECTOR = self.get_setting("AINAS_AI_VISION_PROJECTOR", "services/ai/models/mmproj-model-f16.gguf")
        self.AINAS_AI_GPU_LAYERS = int(self.get_setting("AI_GPU_LAYERS", "32"))
        self.AINAS_DISK_USAGE_THRESHOLD_PCT = float(self.get_setting("AINAS_DISK_USAGE_THRESHOLD_PCT", "90.0"))

        # Elasticsearch Settings
        self.AINAS_ES_URL = self.get_setting("AINAS_ES_URL", "http://localhost:9200")
        self.AINAS_ES_INDEX = self.get_setting("AINAS_ES_INDEX", "ainas")
        self.AINAS_ES_EMBEDDING_DIMS = int(self.get_setting("AINAS_ES_EMBEDDING_DIMS", "768"))

        # Logging
        self.AINAS_LOG_LEVEL = self.get_setting("AINAS_LOG_LEVEL", "INFO").upper()
        self.AINAS_LOG_FILE = self.get_setting("AINAS_LOG_FILE", "../logs/backend.log")
        self.AINAS_LOG_FILE = os.path.expanduser(self.AINAS_LOG_FILE)
        # Resolve relative log path against storage path
        if not os.path.isabs(self.AINAS_LOG_FILE):
            self.AINAS_LOG_FILE = os.path.abspath(os.path.join(self.AINAS_BACKEND_DIR, self.AINAS_LOG_FILE))

        # Side effects: ensure critical directories exist
        os.makedirs(self.AINAS_DATA_PATH, exist_ok=True)
        os.makedirs(self.AINAS_THUMBNAIL_DIR, exist_ok=True)

    def get_setting(self, key: str, default=None):
        """Retrieve setting from YAML file, then environment variable, then default."""
        val = self.file_config.get(key)
        if val is not None:
            return val
        return os.getenv(key, default)

    def save_config(self, updates: dict):
        """Updates the live config and persists changes to the YAML file."""
        # Update live object
        for key, value in updates.items():
            if hasattr(self, key):
                setattr(self, key, value)
                # Also update module-level globals for consistency
                globals()[key] = value
            
            # Map the internal YAML keys
            yaml_key = key.replace("AINAS_", "")
            self.file_config[yaml_key] = value

        # Persist to file
        try:
            with open(self.AINAS_CONFIG_FILE, "w") as f:
                yaml.safe_dump(self.file_config, f, default_flow_style=False)
        except Exception as e:
            logging.getLogger(__name__).error(f"Failed to save config: {e}")

def initialize(backend_dir: Path):
    """
    Initializes the global configuration singleton.
    Populates the module-level globals for backward compatibility.
    """
    global config
    config = AppConfig(backend_dir)

    # Export class attributes to the module level to maintain backward compatibility
    # for existing imports like 'from backend.core.config import AINAS_DATA_PATH'
    for _k, _v in config.__dict__.items():
        if not _k.startswith('_'):
            globals()[_k] = _v
            
    # Now that config is loaded and exported, we can setup logging
    from backend.core.logger import setup_logging
    setup_logging()

    # Flush buffered logs from the initialization phase now that handlers are active
    logger = logging.getLogger(__name__)
    for level, msg in config._init_logs:
        getattr(logger, level)(msg)

    return config
