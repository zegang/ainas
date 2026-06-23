import os
import logging
import asyncio
import time
import uuid
import subprocess
from typing import List, Generator, AsyncGenerator, Dict, Any

from langchain_core.messages import AIMessage, AIMessageChunk, BaseMessage, HumanMessage

from backend.services.ai.agents.nas_agent import create_nas_agent, _auto_query_documents
from backend.services.ai.tools.image_tools import get_image_tools
from backend.services.ai.tools.file_tools import get_file_tools
from backend.services.ai.tools.system_tools import get_system_tools, get_system_stats_summary
from backend.services.monitoring.prometheus import AI_REQUEST_DURATION, AI_TOOL_DURATION
from backend.core import config
from backend.services.system_service import get_disk_usage
from backend.services.elasticsearch_service import ElasticsearchService
from backend.services.ai.features.registry import FeatureRegistry
from backend.services.ai.features.chat import ChatFeature
from backend.services.ai.features.vision import VisionFeature
from backend.services.ai.features.embedding import EmbeddingFeature
from backend.services.huggingface_service import HuggingFaceService
from backend.services.ai.models.ai_status import AIStatus
from backend.db.database import db_manager, FeatureModelRecord

class AIEngine:
    _instance = None

    def __init__(self, status: AIStatus | None = None):
        self.logger = logging.getLogger(__name__)
        self.nas_data_path = config.AINAS_DATA_PATH
        self.api_key = config.AINAS_AI_API_KEY
        self.vision_projector = config.AINAS_AI_VISION_PROJECTOR
        self._status = status
        self.logger.info("Initializing AI Engine, NAS Data Path: %s, Vision Projector: %s",
                         self.nas_data_path, self.vision_projector)

        model_service = HuggingFaceService()
        try:
            model_service.sync_db_from_cache()
        except Exception:
            self.logger.warning("Failed to sync DB from cache", exc_info=True)
        try:
            model_service.restart_unfinished_downloads()
        except Exception:
            self.logger.warning("Failed to restart unfinished model downloads", exc_info=True)

        if status:
            db = db_manager.SessionLocal()
            try:
                count = db.query(FeatureModelRecord).count()
            finally:
                db.close()
            status.models_available = count

        self.features = FeatureRegistry(status=status)
        chat_feature = ChatFeature(model_service=model_service)
        vision_feature = VisionFeature(model_service=model_service)
        embedding_feature = EmbeddingFeature(model_service=model_service)
        self.features.register("chat", chat_feature)
        self.features.register("vision", vision_feature)
        self.features.register("embedding", embedding_feature)

        if status:
            status.sync_features_list(self.features)

        self.logger.info("AI Engine features registered: %s",
                         list(self.features.list_features().keys()))

        # Load the chat model synchronously — the agent executor depends on it.
        self.features.set_feature_model("chat", config.AINAS_AI_CHAT_MODEL)
        if self._status:
            self._status.update_feature_state("chat", config.AINAS_AI_CHAT_MODEL, "ready")
            self._status.sync_features_list(self.features)
        # Vision and embedding can load in the background.
        self.features.set_feature_model_async("vision", config.AINAS_AI_VISION_MODEL)
        self.features.set_feature_model_async("embedding", config.AINAS_EMBEDDING_MODEL)

        vision_feature.chat_feature = chat_feature

        # Initialize RAG Components
        if config.AINAS_ENABLE_AI_RAG:
            self.es_service = ElasticsearchService()
        else:
            self.es_service = None
        self.logger.info("Initializing image, file, and system tools...")
        self.tools = get_image_tools(
            self.nas_data_path,
            self.api_key,
            vision_feature=vision_feature,
        ) + get_file_tools(
            self.nas_data_path,
            es_service=self.es_service,
            embedding_feature=embedding_feature,
        ) + get_system_tools()
        self.agent_executor = create_nas_agent(chat_feature, self.tools)
        self._active_requests: Dict[str, asyncio.Event] = {}

    def _log_resource_usage(self, request_id: str, phase: str):
        usage_str = get_system_stats_summary()
        self.logger.info(f"[Request {request_id}] {phase} Usage -> {usage_str}")

    def _get_cancellation_event(self, request_id: str) -> asyncio.Event:
        if request_id not in self._active_requests:
            self._active_requests[request_id] = asyncio.Event()
        return self._active_requests[request_id]

    def start_request(self, request_id: str):
        self._active_requests[request_id] = asyncio.Event()
        self.logger.info(f"AI request {request_id} started.")

    def cancel_request(self, request_id: str) -> bool:
        event = self._active_requests.get(request_id)
        if event:
            event.set()
            self.logger.info(f"AI request {request_id} cancellation requested.")
            return True
        self.logger.warning(f"AI request {request_id} not found for cancellation.")
        return False

    def end_request(self, request_id: str):
        if request_id in self._active_requests:
            del self._active_requests[request_id]
            self.logger.info(f"AI request {request_id} ended and cleaned up.")

    def __new__(cls, **kwargs):
        if cls._instance is None:
            cls._instance = super(AIEngine, cls).__new__(cls)
        return cls._instance

    @property
    def embeddings(self):
        feature = self.features.get("embedding")
        return feature.embeddings if feature else None

    def generate_tags(self, file_name: str):
        try:
            tag_tool = next((t for t in self.tools if t.name == "tag_image"), None)
            if not tag_tool:
                return ["unclassified"]
            result = tag_tool.invoke({"file_name": file_name})
            if "Failed" in result or "not found" in result:
                return ["unclassified"]
            return [t.strip() for t in result.split(",") if t.strip()]
        except Exception as e:
            self.logger.error("AI tag generation failed: %s", e)
            return ["unclassified"]

    async def chat(self, text: str, filenames: List[str], request_id: str) -> str:
        cancellation_event = self._get_cancellation_event(request_id)
        if cancellation_event.is_set():
            raise asyncio.CancelledError("AI chat request cancelled before starting.")
        prompt_text = text
        if filenames:
            prompt_text += f"\n\n[Attached files: {', '.join([f'\"{f}\"' for f in filenames])}]"
        initial_state = {"messages": [HumanMessage(content=prompt_text)], "filenames": filenames, "cancellation_event": cancellation_event}
        with AI_REQUEST_DURATION.labels(type='chat').time():
            self._log_resource_usage(request_id, "START")
            try:
                result = await self.agent_executor.ainvoke(initial_state)
                self._log_resource_usage(request_id, "END")
                if cancellation_event.is_set():
                    raise asyncio.CancelledError("AI chat request cancelled during processing.")
                final_message = result["messages"][-1]
                return final_message.content if hasattr(final_message, 'content') else str(final_message)
            except asyncio.CancelledError:
                self.logger.info(f"AI chat request {request_id} was cancelled.")
                raise
            except Exception as e:
                self.logger.error("Chat generation failed: %s", e)
                return "I encountered an error while processing your request."

    async def chat_stream(self, text: str, filenames: List[str], request_id: str) -> AsyncGenerator[str, None]:
        cancellation_event = self._get_cancellation_event(request_id)
        if cancellation_event.is_set():
            raise asyncio.CancelledError("AI chat stream request cancelled before starting.")
        prompt_text = text
        if filenames:
            prompt_text += f"\n\n[Attached files: {', '.join([f'\"{f}\"' for f in filenames])}]"
        messages = [HumanMessage(content=prompt_text)]

        # Pre-query documents and yield status before agent execution
        doc_files = [f for f in filenames if f.lower().endswith(('.pdf', '.docx', '.txt', '.md', '.log'))]
        if doc_files:
            yield "[Querying indexed documents for relevant content...]\n"
            doc_content = await _auto_query_documents(messages, doc_files, self.tools)
            if doc_content:
                yield f"[Found relevant content in {len(doc_files)} document(s). Analyzing...]\n"
            else:
                yield "[No indexed content found for the attached documents.]\n"

        initial_state = {"messages": messages, "filenames": filenames, "cancellation_event": cancellation_event}
        with AI_REQUEST_DURATION.labels(type='stream').time():
            tool_start_times = {}
            self._log_resource_usage(request_id, "STREAM_START")
            try:
                async for event in self.agent_executor.astream_events(initial_state, version="v2"):
                    if cancellation_event.is_set():
                        self.logger.info(f"AI request {request_id} cancelled during stream processing.")
                        raise asyncio.CancelledError("AI chat stream request cancelled.")
                    if event["event"] == "on_chat_model_stream":
                        chunk = event["data"]["chunk"]
                        if isinstance(chunk, BaseMessage) and chunk.content:
                            yield chunk.content
                    elif event["event"] == "on_tool_start":
                        tool_start_times[event["run_id"]] = time.perf_counter()
                    elif event["event"] == "on_tool_end":
                        tool_name = event["name"]
                        tool_output = event["data"].get("output")
                        start_time = tool_start_times.pop(event["run_id"], None)
                        duration = time.perf_counter() - start_time if start_time else 0
                        AI_TOOL_DURATION.labels(tool_name=tool_name).observe(duration)
                        if tool_output is not None:
                            content = tool_output.content if hasattr(tool_output, 'content') else str(tool_output)
                            yield f"\n<tool_result>\n[{duration:.2f}s] Tool '{tool_name}' result: {content}\n</tool_result>\n"
                self._log_resource_usage(request_id, "STREAM_END")
            except asyncio.CancelledError:
                self.logger.info(f"AI chat stream request {request_id} was cancelled.")
                raise
            except Exception as e:
                self.logger.error("Stream generation failed: %s", e)
                yield "Error during streaming response."
