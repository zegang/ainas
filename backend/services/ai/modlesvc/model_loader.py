import os
import logging
from typing import Optional
from langchain_openai import ChatOpenAI
from langchain_huggingface import HuggingFacePipeline, ChatHuggingFace, HuggingFaceEmbeddings # type: ignore
from transformers import BlipProcessor, BlipForConditionalGeneration # type: ignore
from backend.services.huggingface_service import HuggingFaceService
from langchain_community.chat_models import ChatLlamaCpp
from backend.core import config

class ModelLoader:
    """Wrapper to handle loading different AI models based on configuration."""
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        # Safely get provider from config (fallback to local if missing)
        self.provider = getattr(config, "AINAS_AI_PROVIDER", "local")
        self.chat_model_name = config.AINAS_AI_CHAT_MODEL
        self.vision_model_name = config.AINAS_AI_VISION_MODEL
        self.image_gen_model_name = config.AINAS_AI_IMAGE_GEN_MODEL
        
        self.api_url = config.AINAS_AI_API_URL
        self.api_key = config.AINAS_AI_API_KEY
        self.gpu_layers = config.AINAS_AI_GPU_LAYERS
        
        # Resolve paths
        self.vision_projector = self._resolve_path(config.AINAS_AI_VISION_PROJECTOR)
        self.nas_data_path = config.AINAS_DATA_PATH
        
        self.llm = None
        self.vision_model = None
        self.embeddings = None
        self.blip_processor = None
        self.blip_model = None
        self._initialize_models()

    def _resolve_path(self, path: str) -> str:
        """Ensures paths are absolute, relative to the backend directory if necessary."""
        if not os.path.isabs(path):
            return os.path.join(config.AINAS_BACKEND_DIR, path)
        return path

    def _initialize_models(self):
        """Instantiates the appropriate LangChain model based on provider."""
        self._init_embeddings()
        self._init_chat_model()
        self._init_vision_model()

    def _init_embeddings(self):
        """Initializes the embedding model for RAG tasks."""
        self.logger.info(f"Initializing embedding model: {config.AINAS_EMBEDDING_MODEL}")
        hf_service = HuggingFaceService()
        try:
            # Pre-download the model snapshot using our custom service to ensure it
            # is placed in the configured cache and respects our logging settings.
            model_path = hf_service.download_snapshot(config.AINAS_EMBEDDING_MODEL)
            self.embeddings = HuggingFaceEmbeddings(
                model_name=model_path,
                cache_folder=config.AINAS_HF_CACHE_DIR
            )
        except Exception as e:
            self.logger.error(f"Failed to download embedding model via HuggingFaceService: {e}")
            self.embeddings = HuggingFaceEmbeddings(
                model_name=config.AINAS_EMBEDDING_MODEL,
                cache_folder=config.AINAS_HF_CACHE_DIR
            )

    def _init_chat_model(self):
        """Initializes the primary LLM for chat interactions."""
        if self.provider == "local":
            if self.chat_model_name.lower().endswith(".gguf"):
                full_model_path = self._resolve_path(self.chat_model_name)
                self.logger.info(f"Loading local GGUF model ({full_model_path}) with {self.gpu_layers} GPU layers...")
                self.llm = ChatLlamaCpp(
                    model_path=full_model_path,
                    max_tokens=2048,
                    n_ctx=8192,
                    n_gpu_layers=self.gpu_layers,
                    f16_kv=True,
                    verbose=True,
                    streaming=True
                )
            else:
                self.logger.info(f"Loading local Hugging Face LLM model ({self.chat_model_name})...")
                self.llm = ChatHuggingFace(llm=HuggingFacePipeline.from_model_id(
                    model_id=self.chat_model_name,
                    task="text-generation",
                    pipeline_kwargs={"max_new_tokens": 512},
                    cache_folder=config.AINAS_HF_CACHE_DIR
                ))
        else:
            self.logger.info(f"Connecting to remote chat provider ({self.provider}) at {self.api_url}...")
            self.llm = ChatOpenAI(
                model=self.chat_model_name,
                openai_api_key=self.api_key,
                base_url=self.api_url,
                streaming=True
            )

    def _init_vision_model(self):
        """Initializes the vision model for image-to-text tasks."""
        if self.provider == "local":
            if self.vision_model_name == self.chat_model_name:
                self.logger.info("Using primary LLM for vision tasks (multimodal).")
                self.vision_model = self.llm
            elif self.vision_model_name.lower().endswith(".gguf"):
                full_vision_path = self._resolve_path(self.vision_model_name)
                self.logger.info(f"Loading dedicated GGUF vision model: {full_vision_path}")
                self.vision_model = ChatLlamaCpp(
                    model_path=full_vision_path,
                    n_gpu_layers=self.gpu_layers,
                    n_ctx=4096
                )
            elif self.vision_model_name == "Salesforce/blip-image-captioning-base":
                self.logger.info(f"Loading BLIP vision model: {self.vision_model_name}")
                hf_service = HuggingFaceService()
                try:
                    model_path = hf_service.download_snapshot(self.vision_model_name)
                    self.blip_processor = BlipProcessor.from_pretrained(model_path)
                    self.blip_model = BlipForConditionalGeneration.from_pretrained(model_path)
                    self.logger.info("BLIP vision model loaded successfully.")
                except Exception as e:
                    self.logger.error(f"Failed to load BLIP model {self.vision_model_name}: {e}")
                    self.blip_processor = None
                    self.blip_model = None
            else:
                self.vision_model = None
                self.logger.info(f"Vision model '{self.vision_model_name}' will use on-demand loading or fallback.")
        else:
            if self.vision_model_name == self.chat_model_name:
                self.vision_model = self.llm
            else:
                self.logger.info(f"Connecting to remote vision provider ({self.provider}) at {self.api_url}...")
                self.vision_model = ChatOpenAI(
                    model=self.vision_model_name,
                    openai_api_key=self.api_key,
                    base_url=self.api_url
                )