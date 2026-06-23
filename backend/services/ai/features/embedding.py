import logging
from typing import List, Optional
from langchain_core.embeddings import Embeddings
from langchain_huggingface import HuggingFaceEmbeddings
from backend.core import config
from backend.services.huggingface_service import HuggingFaceService


class EmbeddingFeature:
    functionality = "embedding"
    feature_title = "Embedding"
    feature_description = "Text embedding and vectorization"

    def __init__(self, model_service=None):
        self.logger = logging.getLogger(__name__)
        self.model_name: Optional[str] = None
        self.embeddings: Optional[Embeddings] = None
        self.model_service = model_service

    def set_embeddings(self, embeddings: Embeddings) -> None:
        self.embeddings = embeddings

    def set_model(self, model_name: str, model_service=None) -> None:
        model_service = model_service or self.model_service
        self.model_name = model_name
        self.logger.info("Initializing embedding model: %s", model_name)
        if model_service:
            info = model_service.resolve_model(model_name)
            model_path = info["path"]
        else:
            svc = HuggingFaceService()
            model_path = svc.download_snapshot(model_name)
        try:
            self.embeddings = HuggingFaceEmbeddings(
                model_name=model_path,
                cache_folder=config.AINAS_HF_CACHE_DIR,
            )
        except Exception as e:
            self.logger.error("Failed to load embedding model: %s", e)
            self.embeddings = HuggingFaceEmbeddings(
                model_name=model_name,
                cache_folder=config.AINAS_HF_CACHE_DIR,
            )

    async def embed_query(self, text: str) -> Optional[List[float]]:
        if not self.embeddings:
            self.logger.warning("Embedding model not available")
            return None
        try:
            return await self.embeddings.aembed_query(text)
        except Exception as e:
            self.logger.error("Query embedding failed: %s", e)
            return None

    async def embed_documents(self, texts: List[str]) -> Optional[List[List[float]]]:
        if not self.embeddings:
            self.logger.warning("Embedding model not available")
            return None
        try:
            return await self.embeddings.aembed_documents(texts)
        except Exception as e:
            self.logger.error("Document embedding failed: %s", e)
            return None
