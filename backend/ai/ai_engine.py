import os
import logging
import io
from typing import List
from PIL import Image
from transformers import pipeline, AutoModelForCausalLM, AutoTokenizer
from langchain_openai import ChatOpenAI
from langchain_huggingface import HuggingFacePipeline, ChatHuggingFace
from langchain_core.messages import HumanMessage
from langchain_community.chat_models import ChatLlamaCpp

from backend.ai.tools.file_tools import get_file_tools
from backend.ai.tools.image_tools import get_image_tools
from backend.ai.agents.nas_agent import create_nas_agent

logger = logging.getLogger(__name__)

# Project Root calculation
BASE_DIR = os.getenv("AI_NAS_BACKEND_BASE_DIR")

class AIEngine:
    def __init__(self):
        # LLM Configuration for Chat Assistant
        self.provider = os.getenv("AI_PROVIDER", "local").lower()
        self.model_name = os.getenv("AI_MODEL", "ai/models/Qwen3-1.7B-Q8_0.gguf")
        if not os.path.isabs(self.model_name):
            self.model_name = os.path.join(BASE_DIR, self.model_name)
            
        self.api_url = os.getenv("AI_API_URL", "https://api.openai.com/v1")
        self.api_key = os.getenv("AI_API_KEY", "")
        self.storage_path = os.path.join(BASE_DIR, "../data")

        self.vision_model = None

        if self.provider == "local":
            if self.model_name.lower().endswith(".gguf"):
                logger.info(f"Loading local GGUF model ({self.model_name})...")
                self.llm = ChatLlamaCpp(
                    model_path=self.model_name,
                    max_tokens=512,
                    n_ctx=4096,
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

        # 3. Setup Tools and Agent
        self.tools = get_image_tools(self.storage_path, self.api_key)
        self.tools.extend(get_file_tools(self.storage_path))
        self.agent_executor = create_nas_agent(self.llm, self.tools)

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

    def chat(self, text: str, filenames: List[str] = None):
        """Generates a complete response for a given user prompt using the NAS Agent."""
        try:
            # Formulate a structured prompt to guide the agent in using tools on provisioned files
            prompt = text
            if filenames:
                files_list = ", ".join([f'"{f}"' for f in filenames])
                prompt = (
                    f"User Request: {text}\n\n"
                    f"[NAS CONTEXT: The user is currently focusing on these files: {files_list}. "
                    "Use your tools to inspect, explain, or search these specific files if relevant to the request.]"
                )
            logger.info(f"Inputs: {text=}, {filenames=}")
            result = self.agent_executor.invoke({"messages": [HumanMessage(content=prompt)]})
            logger.info("Agent response: %s", result["messages"][-1].content)
            return result["messages"][-1].content
        except Exception as e:
            logger.error("Chat generation failed: %s", e)
            return "I encountered an error while processing your request."

    def chat_stream(self, text: str, filenames: List[str] = None):
        """Streams the agent response token by token for real-time interaction."""
        try:
            prompt = text
            if filenames:
                files_list = ", ".join([f'"{f}"' for f in filenames])
                prompt = (
                    f"User Request: {text}\n\n"
                    f"[NAS CONTEXT: The user is currently focusing on these files: {files_list}. "
                    "Use your tools to inspect, explain, or search these specific files if relevant to the request.]"
                )

            logger.info(f"Inputs: {text=}, {filenames=}")
            # Stream chunks from the compiled graph
            for event in self.agent_executor.stream({"messages": [HumanMessage(content=prompt)]}, stream_mode="messages"):
                chunk, metadata = event
                if metadata.get("langgraph_node") == "agent" and hasattr(chunk, 'content'):
                    if chunk.content:
                        logger.info(f"yield {chunk.content=}")
                        yield chunk.content
        except Exception as e:
            logger.error("Stream generation failed: %s", e)
            yield "Error during streaming response."