import os
import logging
import asyncio
import uuid
import subprocess
from typing import List, Generator, AsyncGenerator, Dict, Any

from langchain_core.messages import AIMessage, AIMessageChunk, BaseMessage, HumanMessage
from langchain_openai import ChatOpenAI
from langchain_huggingface import HuggingFacePipeline, ChatHuggingFace
from langchain_community.chat_models import ChatLlamaCpp
from langchain_community.llms import Ollama # Example LLM

from backend.ai.tools.file_tools import get_file_tools
from backend.ai.tools.image_tools import get_image_tools
from backend.ai.agents.nas_agent import create_nas_agent
from backend.ai.tools.image_tools import get_image_tools
from backend.ai.tools.file_tools import get_file_tools
from backend.monitoring.prometheus import AI_REQUEST_DURATION # New import for monitoring

logger = logging.getLogger(__name__)

# Project Root calculation
BASE_DIR = os.getenv("AI_NAS_BACKEND_BASE_DIR")

class AIEngine:
    _instance = None # Singleton instance
    def __init__(self):
        # LLM Configuration for Chat Assistant
        self.provider = os.getenv("AI_PROVIDER", "local").lower()
        self.model_name = os.getenv("AI_MODEL", "ai/models/Qwen3-1.7B-Q8_0.gguf")
        if not os.path.isabs(self.model_name):
            self.model_name = os.path.join(BASE_DIR, self.model_name)
            
        self.api_url = os.getenv("AI_API_URL", "https://api.openai.com/v1")
        self.api_key = os.getenv("AI_API_KEY", "")
        self.storage_path = os.path.join(BASE_DIR, "../data")
        self.gpu_layers = int(os.getenv("AI_GPU_LAYERS", "32")) # Default to 32 layers for GPU offloading

        self.vision_model = None

        if self.provider == "local":
            if self.model_name.lower().endswith(".gguf"):
                logger.info(f"Loading local GGUF model ({self.model_name}) with {self.gpu_layers} GPU layers...")
                self.llm = ChatLlamaCpp(
                    model_path=self.model_name,
                    max_tokens=512,
                    n_ctx=4096,
                    n_gpu_layers=self.gpu_layers,
                    f16_kv=True,
                    verbose=True, # Enables internal llama-cpp hardware logging
                    streaming=True,
                )
                self.vision_model = self.llm
            else:
                logger.info(f"Loading local LLM model ({self.model_name})...")
                # Note: Local vision support requires specific VLM models (e.g. Llava)
                self.llm = ChatHuggingFace(llm=HuggingFacePipeline.from_model_id(
                    model_id=self.model_name,
                    task="text-generation",
                    pipeline_kwargs={"max_new_tokens": 512}
                ))
        else:
            self.llm = ChatOpenAI(
                model=self.model_name,
                openai_api_key=self.api_key,
                base_url=self.api_url,
                streaming=True
            )

        # Setup Tools and Agent
        # self.tools = get_nas_tools() # Combined tools
        self.tools = get_image_tools(self.storage_path, self.api_key) + get_file_tools(self.storage_path)
        self.agent_executor = create_nas_agent(self.llm, self.tools)
        self._active_requests: Dict[str, asyncio.Event] = {}

    def _log_resource_usage(self, request_id: str, phase: str):
        """Logs current CPU and GPU utilization percentages."""
        stats = []
        try:
            import psutil
            cpu_pct = psutil.cpu_percent(interval=None)
            mem_pct = psutil.virtual_memory().percent
            stats.append(f"CPU: {cpu_pct}%")
            stats.append(f"RAM: {mem_pct}%")
        except ImportError:
            stats.append("CPU/RAM: psutil not installed")

        # Attempt to get GPU stats via nvidia-smi
        try: # NVIDIA GPU
            nvidia_res = subprocess.check_output(
                ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used", "--format=csv,noheader,nounits"],
                encoding='utf-8'
            )
            nvidia_info = nvidia_res.strip().replace("\n", " | ")
            stats.append(f"NVIDIA GPU (Util, Mem): {nvidia_info}")
        except (subprocess.CalledProcessError, FileNotFoundError):
            # nvidia-smi not found or no NVIDIA GPUs
            pass

        # Attempt to get AMD GPU stats via rocm-smi
        try: # AMD GPU
            # Get GPU utilization
            roc_gpu_util_res = subprocess.check_output(
                ["rocm-smi", "--showuse", "--csv"],
                encoding='utf-8'
            )
            gpu_util_pct = "N/A"
            gpu_util_lines = roc_gpu_util_res.strip().split('\n')
            if len(gpu_util_lines) > 1:
                # Skip header, get first GPU's data, GPU% is the last column (index 9)
                gpu_data = gpu_util_lines[1].split(',')
                if len(gpu_data) > 9:
                    gpu_util_pct = gpu_data[9].strip()

            # Get VRAM utilization
            roc_vram_util_res = subprocess.check_output(
                ["rocm-smi", "--showmeminfo", "VRAM", "--csv"],
                encoding='utf-8'
            )
            vram_util_pct = "N/A"
            vram_util_lines = roc_vram_util_res.strip().split('\n')
            if len(vram_util_lines) > 1:
                # Skip header, get first GPU's data, VRAM% is the second column (index 1)
                vram_data = vram_util_lines[1].split(',')
                if len(vram_data) > 1:
                    vram_util_pct = vram_data[1].strip()

            if gpu_util_pct != "N/A" or vram_util_pct != "N/A":
                stats.append(f"AMD GPU (Util: {gpu_util_pct}, VRAM: {vram_util_pct})")
            else:
                stats.append("AMD GPU: N/A or no AMD driver")

        except (subprocess.CalledProcessError, FileNotFoundError):
            # rocm-smi not found or no AMD GPUs
            pass
        except Exception as e:
            logger.warning(f"Error parsing rocm-smi output: {e}")
            stats.append("AMD GPU: Error parsing output")

        usage_str = " | ".join(stats)
        logger.info(f"[Request {request_id}] {phase} Usage -> {usage_str}")

    def _get_cancellation_event(self, request_id: str) -> asyncio.Event:
        """Retrieves or creates a cancellation event for a given request ID."""
        if request_id not in self._active_requests:
            self._active_requests[request_id] = asyncio.Event()
        return self._active_requests[request_id]

    def start_request(self, request_id: str):
        """Registers a new request and creates a cancellation event for it."""
        self._active_requests[request_id] = asyncio.Event()
        logger.info(f"AI request {request_id} started.")

    def cancel_request(self, request_id: str) -> bool:
        """Sets the cancellation event for a specific request."""
        event = self._active_requests.get(request_id)
        if event:
            event.set()
            logger.info(f"AI request {request_id} cancellation requested.")
            return True
        logger.warning(f"AI request {request_id} not found for cancellation.")
        return False

    def end_request(self, request_id: str):
        """Cleans up the cancellation event for a completed or cancelled request."""
        if request_id in self._active_requests:
            del self._active_requests[request_id]
            logger.info(f"AI request {request_id} ended and cleaned up.")

    # Singleton pattern
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(AIEngine, cls).__new__(cls)
        return cls._instance

    # Placeholder for get_nas_tools if it's not defined elsewhere
    # This is a temporary fix if get_nas_tools is not yet implemented
    # In a real scenario, you'd have a backend.ai.tools module with this function
    # def get_nas_tools(self):
    #     return get_image_tools(self.storage_path, self.api_key) + get_file_tools(self.storage_path)

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
            logger.error("AI tag generation failed: %s", e)
            return ["unclassified"]

    async def chat(self, text: str, filenames: List[str], request_id: str) -> str:
        """Generates a complete response for a given user prompt using the NAS Agent."""
        cancellation_event = self._get_cancellation_event(request_id)
        if cancellation_event.is_set():
            raise asyncio.CancelledError("AI chat request cancelled before starting.")

        initial_state = {"messages": [HumanMessage(content=text)], "filenames": filenames, "cancellation_event": cancellation_event}
        
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
                logger.info(f"AI chat request {request_id} was cancelled.")
                raise
            except Exception as e:
                logger.error("Chat generation failed: %s", e)
                return "I encountered an error while processing your request."

    async def chat_stream(self, text: str, filenames: List[str], request_id: str) -> AsyncGenerator[str, None]:
        """Streams the agent response token by token for real-time interaction."""
        cancellation_event = self._get_cancellation_event(request_id)
        if cancellation_event.is_set():
            raise asyncio.CancelledError("AI chat stream request cancelled before starting.")

        initial_state = {"messages": [HumanMessage(content=text)], "filenames": filenames, "cancellation_event": cancellation_event}

        with AI_REQUEST_DURATION.labels(type='stream').time():
            self._log_resource_usage(request_id, "STREAM_START")
            try:
                # Use astream_events (v2) to capture internal LLM tokens in real-time
                async for event in self.agent_executor.astream_events(initial_state, version="v2"):
                    if cancellation_event.is_set():
                        logger.info(f"AI request {request_id} cancelled during stream processing.")
                        raise asyncio.CancelledError("AI chat stream request cancelled.")

                    if event["event"] == "on_chat_model_stream":
                        chunk = event["data"]["chunk"]
                        if isinstance(chunk, BaseMessage) and chunk.content:
                            yield chunk.content
                self._log_resource_usage(request_id, "STREAM_END")
            except asyncio.CancelledError:
                logger.info(f"AI chat stream request {request_id} was cancelled.")
                raise
            except Exception as e:
                logger.error("Stream generation failed: %s", e)
                yield "Error during streaming response."