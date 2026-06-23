import os
import logging
from typing import AsyncGenerator, Optional
from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage
from langchain_community.chat_models import ChatLlamaCpp
from langchain_huggingface import HuggingFacePipeline, ChatHuggingFace
from langchain_openai import ChatOpenAI
from backend.core import config


class ChatFeature:
    functionality = "chat"
    feature_title = "Chat"
    feature_description = "Conversational AI assistant"

    def __init__(self, model_service=None):
        self.logger = logging.getLogger(__name__)
        self.model_name: Optional[str] = None
        self.llm: Optional[BaseChatModel] = None
        self.model_service = model_service

    def _resolve_path(self, path: str) -> str:
        if not os.path.isabs(path):
            return os.path.join(config.AINAS_BACKEND_DIR, path)
        return path

    def set_llm(self, llm: BaseChatModel) -> None:
        self.llm = llm

    def set_model(self, model_name: str, model_service=None) -> None:
        model_service = model_service or self.model_service
        self.model_name = model_name

        if model_service:
            info = model_service.resolve_model(model_name)
            if info.get("is_local"):
                if info["type"] == "gguf":
                    self.logger.info("Loading GGUF chat model: %s", info["path"])
                    self.llm = ChatLlamaCpp(
                        model_path=info["path"],
                        max_tokens=2048,
                        n_ctx=8192,
                        n_gpu_layers=config.AINAS_AI_GPU_LAYERS,
                        f16_kv=True,
                        verbose=True,
                        streaming=True,
                    )
                else:
                    self.logger.info("Loading Hugging Face chat model: %s", info["path"])
                    self.llm = ChatHuggingFace(llm=HuggingFacePipeline.from_model_id(
                        model_id=info["path"],
                        task="text-generation",
                        pipeline_kwargs={"max_new_tokens": 512},
                        cache_folder=config.AINAS_HF_CACHE_DIR,
                    ))
            else:
                self.logger.info("Connecting to remote chat provider: %s", model_name)
                self.llm = ChatOpenAI(
                    model=model_name,
                    openai_api_key=config.AINAS_AI_API_KEY,
                    base_url=config.AINAS_AI_API_URL,
                    streaming=True,
                )
        elif model_name.lower().endswith(".gguf"):
            model_path = self._resolve_path(model_name)
            self.logger.info("Loading GGUF chat model: %s", model_path)
            self.llm = ChatLlamaCpp(
                model_path=model_path,
                max_tokens=2048,
                n_ctx=8192,
                n_gpu_layers=config.AINAS_AI_GPU_LAYERS,
                f16_kv=True,
                verbose=True,
                streaming=True,
            )
        else:
            self.logger.info("Loading Hugging Face chat model: %s", model_name)
            self.llm = ChatHuggingFace(llm=HuggingFacePipeline.from_model_id(
                model_id=model_name,
                task="text-generation",
                pipeline_kwargs={"max_new_tokens": 512},
                cache_folder=config.AINAS_HF_CACHE_DIR,
            ))

    async def generate(self, prompt: str) -> str:
        if not self.llm:
            return "Chat model is not set."
        try:
            response = await self.llm.ainvoke([HumanMessage(content=prompt)])
            return response.content if hasattr(response, "content") else str(response)
        except Exception as e:
            self.logger.error("Chat generation failed: %s", e)
            return "I encountered an error while processing your request."

    async def generate_stream(self, prompt: str) -> AsyncGenerator[str, None]:
        if not self.llm:
            yield "Chat model is not set."
            return
        try:
            async for chunk in self.llm.astream([HumanMessage(content=prompt)]):
                if chunk.content:
                    yield chunk.content
        except Exception as e:
            self.logger.error("Chat stream failed: %s", e)
            yield "Error during streaming response."
