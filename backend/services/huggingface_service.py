import os
import logging
from typing import List, Dict, Any
from huggingface_hub import HfApi, hf_hub_download, snapshot_download
from huggingface_hub.errors import RepositoryNotFoundError, RevisionNotFoundError
from backend.core import config

class HuggingFaceService:
    """
    Service to handle Hugging Face model searching, local listing, and downloading.
    """

    def __init__(self):
        # Use None if token is empty string to avoid illegal "Bearer " header issues.
        # Passing an empty string results in an invalid 'Authorization: Bearer ' header.
        self.token = config.AINAS_HF_API_TOKEN if config.AINAS_HF_API_TOKEN else None
        self.api = HfApi(token=self.token)
        self.cache_dir = config.AINAS_HF_CACHE_DIR
        self.models_dir = config.AINAS_AI_MODELS_DIR

    def search_models(self, query: str = "gguf", limit: int = 15) -> List[Dict[str, Any]]:
        """
        Searches Hugging Face Hub for models matching the query, filtered by GGUF tags.
        """
        logger = logging.getLogger(__name__)
        try:
            models = self.api.list_models(
                search=query,
                tags="gguf",
                limit=limit,
                sort="downloads",
                direction=-1
            )
            return [{"id": m.modelId, "downloads": getattr(m, 'downloads', 0)} for m in models]
        except Exception as e:
            logger.error("Hugging Face Hub search failed: %s", e)
            raise

    def list_local_models(self) -> List[str]:
        """
        Lists all .gguf model files currently stored in the local models directory.
        """
        logger = logging.getLogger(__name__)
        try:
            if not os.path.exists(self.models_dir):
                return []
            return [f for f in os.listdir(self.models_dir) if f.endswith(".gguf")]
        except Exception as e:
            logger.error("Failed to list local models in %s: %s", self.models_dir, e)
            raise
    
    def is_model_downloaded(self, repo_id: str, filename: str) -> bool:
        """
        Checks if a specific model file from a Hugging Face repository 
        is already present and valid in the local storage.
        """
        # Models are stored in the path defined in config
        target_path = os.path.join(config.AINAS_MODEL_PATH, filename)
        
        if os.path.exists(target_path):
            # Ensure the file is not empty (e.g., from a failed previous attempt)
            return os.path.getsize(target_path) > 0
        return False

    def download_model(self, repo_id: str, filename: str) -> str:
        """
        Downloads a specific model file from a repository into the configured HF cache directory if not already present.
        """
        logger = logging.getLogger(__name__)
        if self.is_model_downloaded(repo_id, filename):
            target_path = os.path.join(config.AINAS_MODEL_PATH, filename)
            logging.getLogger(__name__).info(
                f"Model {filename} already exists at {target_path}. Skipping download."
            )
            return target_path

        try:
            logger.info("Downloading %s from %s into %s...", filename, repo_id, self.cache_dir)
            
            # Ensure the cache directory exists
            os.makedirs(self.cache_dir, exist_ok=True)
            
            path = hf_hub_download(
                repo_id=repo_id,
                filename=filename,
                local_dir=self.cache_dir,
                token=self.token
            )
            logger.info("Model downloaded successfully to %s", path)
            return path

        except RepositoryNotFoundError:
            logger.error("Hugging Face repository not found: %s", repo_id)
            raise ValueError(f"Repository '{repo_id}' not found.")
            
        except RevisionNotFoundError:
            logger.error("Hugging Face revision not found for repo: %s", repo_id)
            raise ValueError(f"Revision/branch not found for repository '{repo_id}'.")
            
        except Exception as e:
            logger.error("Unexpected error during model download: %s", e)
            raise

    def download_snapshot(self, repo_id: str) -> str:
        """
        Downloads a full repository from Hugging Face into a subdirectory of the cache.
        """
        logger = logging.getLogger(__name__)
        try:
            repo_path = os.path.join(self.cache_dir, "repos", repo_id.replace("/", "--"))
            logger.info("Downloading snapshot for %s in %s...", repo_id, repo_path)
            return snapshot_download(
                repo_id=repo_id,
                local_dir=repo_path,
                token=self.token
            )
        except Exception as e:
            logger.error("Failed to download snapshot for %s: %s", repo_id, e)
            raise

    def remove_local_model(self, filename: str):
        """
        Deletes a model file from the local models directory.
        """
        logger = logging.getLogger(__name__)
        file_path = os.path.join(self.models_dir, filename)
        if os.path.exists(file_path):
            os.remove(file_path)
            logger.info("Deleted local model file: %s", filename)
        else:
            logger.warning("Attempted to delete non-existent model file: %s", filename)