import os
import logging
import asyncio
import time
import uuid
import subprocess
from typing import List, Generator, AsyncGenerator, Dict, Any

from langchain_core.messages import AIMessage, AIMessageChunk, BaseMessage, HumanMessage

from backend.services.ai.agents.nas_agent import create_nas_agent
from backend.services.ai.modlesvc.model_loader import ModelLoader
from backend.services.ai.tools.image_tools import get_image_tools
from backend.services.ai.tools.file_tools import get_file_tools
from backend.services.ai.tools.system_tools import get_system_tools, get_system_stats_summary
from backend.services.monitoring.prometheus import AI_REQUEST_DURATION, AI_TOOL_DURATION # New import for monitoring
from backend.core import config
from backend.services.system_service import get_disk_usage
from backend.services.elasticsearch_service import ElasticsearchService
class AIEngine:
    _instance = None # Singleton instance
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        # Load Models via specialized service
        model_loader = ModelLoader()
        self.llm = model_loader.llm
        self.vision_model = model_loader.vision_model
        self.vision_projector = model_loader.vision_projector
        self.nas_data_path = model_loader.nas_data_path
        self.api_key = model_loader.api_key
        self.embeddings = model_loader.embeddings
        self.blip_processor = model_loader.blip_processor
        self.blip_model = model_loader.blip_model

        # Initialize RAG Components
        self.es_service = ElasticsearchService()
        self.tools = get_image_tools(
            self.nas_data_path, 
            self.api_key,
            blip_processor=self.blip_processor,
            blip_model=self.blip_model
        ) + get_file_tools(
            self.nas_data_path, 
            es_service=self.es_service, 
            embeddings=self.embeddings
        ) + get_system_tools()
        self.agent_executor = create_nas_agent(self.llm, self.tools)
        self._active_requests: Dict[str, asyncio.Event] = {}

    def _log_resource_usage(self, request_id: str, phase: str):
        """Logs current CPU and GPU utilization percentages."""
        usage_str = get_system_stats_summary()
        self.logger.info(f"[Request {request_id}] {phase} Usage -> {usage_str}")

    def _get_cancellation_event(self, request_id: str) -> asyncio.Event:
        """Retrieves or creates a cancellation event for a given request ID."""
        if request_id not in self._active_requests:
            self._active_requests[request_id] = asyncio.Event()
        return self._active_requests[request_id]

    def start_request(self, request_id: str):
        """Registers a new request and creates a cancellation event for it."""
        self._active_requests[request_id] = asyncio.Event()
        self.logger.info(f"AI request {request_id} started.")

    def cancel_request(self, request_id: str) -> bool:
        """Sets the cancellation event for a specific request."""
        event = self._active_requests.get(request_id)
        if event:
            event.set()
            self.logger.info(f"AI request {request_id} cancellation requested.")
            return True
        self.logger.warning(f"AI request {request_id} not found for cancellation.")
        return False

    def end_request(self, request_id: str):
        """Cleans up the cancellation event for a completed or cancelled request."""
        if request_id in self._active_requests:
            del self._active_requests[request_id]
            self.logger.info(f"AI request {request_id} ended and cleaned up.")

    # Singleton pattern
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(AIEngine, cls).__new__(cls)
        return cls._instance

    def generate_tags(self, file_name: str):
        """Generates tags for a file using the tag_image tool from image_tools."""
        try:
            # Find the tag_image tool in the pre-initialized tools list
            tag_tool = next((t for t in self.tools if t.name == "tag_image"), None)
            if not tag_tool:
                return ["unclassified"]

            # Invoke the tool which utilizes the GGUF vision model
            result = tag_tool.invoke({"file_name": file_name})
            if "Failed" in result or "not found" in result:
                return ["unclassified"]

            # Parse the comma-separated string returned by the VLM into a list
            return [t.strip() for t in result.split(",") if t.strip()]
        except Exception as e:
            self.logger.error("AI tag generation failed: %s", e)
            return ["unclassified"]

    async def chat(self, text: str, filenames: List[str], request_id: str) -> str:
        """Generates a complete response for a given user prompt using the NAS Agent."""
        cancellation_event = self._get_cancellation_event(request_id)
        if cancellation_event.is_set():
            raise asyncio.CancelledError("AI chat request cancelled before starting.")

        # Explicitly mention attached files in the prompt so the LLM knows it can use tools on them
        prompt_text = text
        if filenames:
            prompt_text += f"\n\n[Attached files: {', '.join([f'\"{f}\"' for f in filenames])}]"

        initial_state = {"messages": [HumanMessage(content=prompt_text)], "filenames": filenames, "cancellation_event": cancellation_event}
        
        with AI_REQUEST_DURATION.labels(type='chat').time():
            self._log_resource_usage(request_id, "START")
            try:
                result = await self.agent_executor.ainvoke(initial_state) # Use ainvoke for async graph
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
        """Streams the agent response token by token for real-time interaction."""
        cancellation_event = self._get_cancellation_event(request_id)
        if cancellation_event.is_set():
            raise asyncio.CancelledError("AI chat stream request cancelled before starting.")

        # Explicitly mention attached files in the prompt for streaming as well
        prompt_text = text
        if filenames:
            prompt_text += f"\n\n[Attached files: {', '.join([f'\"{f}\"' for f in filenames])}]"

        initial_state = {"messages": [HumanMessage(content=prompt_text)], "filenames": filenames, "cancellation_event": cancellation_event}

        with AI_REQUEST_DURATION.labels(type='stream').time():
            tool_start_times = {} # Track individual tool timings
            self._log_resource_usage(request_id, "STREAM_START")
            try:
                # Use astream_events (v2) to capture internal LLM tokens in real-time
                async for event in self.agent_executor.astream_events(initial_state, version="v2"):
                    if cancellation_event.is_set():
                        self.logger.info(f"AI request {request_id} cancelled during stream processing.")
                        raise asyncio.CancelledError("AI chat stream request cancelled.")

                    if event["event"] == "on_chat_model_stream":
                        chunk = event["data"]["chunk"]
                        if isinstance(chunk, BaseMessage) and chunk.content:
                            yield chunk.content

                    elif event["event"] == "on_tool_start":
                        # Record the start time for this specific tool run
                        tool_start_times[event["run_id"]] = time.perf_counter()

                    elif event["event"] == "on_tool_end":
                        # Stream the result of the tool call so the UI can display it
                        tool_name = event["name"]
                        tool_output = event["data"].get("output")
                        
                        # Calculate duration
                        start_time = tool_start_times.pop(event["run_id"], None)
                        duration = time.perf_counter() - start_time if start_time else 0
                        AI_TOOL_DURATION.labels(tool_name=tool_name).observe(duration)

                        if tool_output is not None:
                            # Extract content from ToolMessage or convert result to string
                            content = tool_output.content if hasattr(tool_output, 'content') else str(tool_output)
                            # Yield wrapped in a custom tag for the frontend to parse
                            yield f"\n<tool_result>\n[{duration:.2f}s] Tool '{tool_name}' result: {content}\n</tool_result>\n"

                self._log_resource_usage(request_id, "STREAM_END")
            except asyncio.CancelledError:
                self.logger.info(f"AI chat stream request {request_id} was cancelled.")
                raise
            except Exception as e:
                self.logger.error("Stream generation failed: %s", e)
                yield "Error during streaming response."