import json
import os
import shutil
import logging
from typing import List, Dict, Any
from huggingface_hub import HfApi, hf_hub_download, snapshot_download
from huggingface_hub.errors import RepositoryNotFoundError, RevisionNotFoundError
from backend.core import config
from backend.db.database import SessionLocal, AiModelRecord

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

    def is_snapshot_downloaded(self, repo_id: str) -> bool:
        """
        Checks whether a snapshot is recorded in the database and its local path still exists.
        """
        db = SessionLocal()
        try:
            record = db.query(AiModelRecord).filter_by(name=repo_id, provider="huggingface").first()
            if record is None:
                return False
            return record.api_base is not None and os.path.exists(record.api_base)
        except Exception:
            return False
        finally:
            db.close()

    def download_snapshot(self, repo_id: str) -> str:
        """
        Downloads a full repository from Hugging Face into a subdirectory of the cache.
        Records the model in the database on success.
        """
        logger = logging.getLogger(__name__)
        repo_path = os.path.join(self.cache_dir, "repos", repo_id.replace("/", "--"))

        if self.is_snapshot_downloaded(repo_id):
            logger.info("Snapshot %s already downloaded at %s. Skipping.", repo_id, repo_path)
            return repo_path

        try:
            logger.info("Downloading snapshot for %s in %s...", repo_id, repo_path)
            downloaded_path = snapshot_download(
                repo_id=repo_id,
                local_dir=repo_path,
                token=self.token
            )

            try:
                info = self.api.model_info(repo_id)
                config_data = {
                    "pipeline_tag": getattr(info, "pipeline_tag", None),
                    "downloads": getattr(info, "downloads", 0),
                    "likes": getattr(info, "likes", 0),
                    "tags": list(getattr(info, "tags", [])),
                    "siblings": [s.rfilename for s in getattr(info, "siblings", [])],
                }
                super_params = json.dumps(config_data)
            except Exception:
                logger.warning("Could not fetch model info for %s", repo_id)
                super_params = None

            db = SessionLocal()
            try:
                existing = db.query(AiModelRecord).filter_by(name=repo_id).first()
                if existing:
                    existing.provider = "huggingface"
                    existing.api_base = downloaded_path
                    existing.config = super_params
                else:
                    record = AiModelRecord(
                        name=repo_id,
                        provider="huggingface",
                        model_type="snapshot",
                        api_base=downloaded_path,
                        config=super_params,
                    )
                    db.add(record)
                db.commit()
            except Exception:
                logger.warning("Failed to record snapshot in database", exc_info=True)
                db.rollback()
            finally:
                db.close()

            return downloaded_path

        except Exception as e:
            logger.error("Failed to download snapshot for %s: %s", repo_id, e)
            raise

    def remove_snapshot(self, repo_id: str):
        """
        Deletes a downloaded snapshot from disk and removes its database record.
        """
        logger = logging.getLogger(__name__)
        repo_path = os.path.join(self.cache_dir, "repos", repo_id.replace("/", "--"))
        if os.path.exists(repo_path):
            shutil.rmtree(repo_path)
            logger.info("Deleted snapshot directory for %s", repo_id)
        else:
            logger.warning("Snapshot directory not found for %s", repo_id)

        db = SessionLocal()
        try:
            record = db.query(AiModelRecord).filter_by(name=repo_id).first()
            if record:
                db.delete(record)
                db.commit()
                logger.info("Removed database record for snapshot %s", repo_id)
            else:
                logger.warning("No database record found for snapshot %s", repo_id)
        except Exception:
            logger.warning("Failed to remove database record for snapshot %s", repo_id, exc_info=True)
            db.rollback()
        finally:
            db.close()

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