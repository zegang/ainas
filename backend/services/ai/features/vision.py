import base64
import logging
import os
import re
from typing import Optional
from PIL import Image
from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_community.chat_models import ChatLlamaCpp
from langchain_openai import ChatOpenAI
from transformers import BlipProcessor, BlipForConditionalGeneration
from backend.core import config
from backend.services.huggingface_service import HuggingFaceService


class VisionFeature:
    functionality = "vision"
    feature_title = "Vision"
    feature_description = "Image analysis and understanding"

    def __init__(self, model_service=None):
        self.logger = logging.getLogger(__name__)
        self.model_name: Optional[str] = None
        self.vision_model: Optional[BaseChatModel] = None
        self.blip_processor: Optional[BlipProcessor] = None
        self.blip_model: Optional[BlipForConditionalGeneration] = None
        self.chat_feature: Optional[object] = None
        self.model_service = model_service

    def set_vision_model(self, model: BaseChatModel) -> None:
        self.vision_model = model

    def set_blip(self, processor: BlipProcessor, model: BlipForConditionalGeneration) -> None:
        self.blip_processor = processor
        self.blip_model = model

    def set_chat_feature(self, chat_feature: object) -> None:
        self.chat_feature = chat_feature

    def _resolve_path(self, path: str) -> str:
        if not os.path.isabs(path):
            return os.path.join(config.AINAS_BACKEND_DIR, path)
        return path

    def set_model(self, model_name: str, model_service=None) -> None:
        model_service = model_service or self.model_service
        self.model_name = model_name

        if model_service:
            info = model_service.resolve_model(model_name)
            if info.get("is_local"):
                if info["type"] == "gguf":
                    self.logger.info("Loading GGUF vision model: %s", info["path"])
                    self.vision_model = ChatLlamaCpp(
                        model_path=info["path"],
                        n_gpu_layers=config.AINAS_AI_GPU_LAYERS,
                        n_ctx=4096,
                    )
                elif "blip" in model_name.lower():
                    self.logger.info("Loading BLIP vision model: %s", info["path"])
                    try:
                        self.blip_processor = BlipProcessor.from_pretrained(info["path"])
                        self.blip_model = BlipForConditionalGeneration.from_pretrained(info["path"])
                    except Exception as e:
                        self.logger.error("Failed to load BLIP model: %s", e)
                        self.blip_processor = None
                        self.blip_model = None
                else:
                    self.logger.info("Vision model '%s' will use on-demand loading.", model_name)
                    self.vision_model = None
            else:
                self.logger.info("Connecting to remote vision provider: %s", model_name)
                self.vision_model = ChatOpenAI(
                    model=model_name,
                    openai_api_key=config.AINAS_AI_API_KEY,
                    base_url=config.AINAS_AI_API_URL,
                )
        elif model_name.lower().endswith(".gguf"):
            model_path = self._resolve_path(model_name)
            self.logger.info("Loading GGUF vision model: %s", model_path)
            self.vision_model = ChatLlamaCpp(
                model_path=model_path,
                n_gpu_layers=config.AINAS_AI_GPU_LAYERS,
                n_ctx=4096,
            )
        elif "blip" in model_name.lower():
            self.logger.info("Loading BLIP vision model: %s", model_name)
            svc = HuggingFaceService()
            try:
                model_path = svc.download_snapshot(model_name)
                self.blip_processor = BlipProcessor.from_pretrained(model_path)
                self.blip_model = BlipForConditionalGeneration.from_pretrained(model_path)
            except Exception as e:
                self.logger.error("Failed to load BLIP model: %s", e)
                self.blip_processor = None
                self.blip_model = None
        else:
            self.logger.info("Vision model '%s' will use on-demand loading.", model_name)
            self.vision_model = None

    def tag_image(self, image_path: str) -> str:
        try:
            if not os.path.exists(image_path):
                return f"File '{image_path}' not found."

            if self.blip_processor and self.blip_model:
                inputs = self.blip_processor(
                    Image.open(image_path).convert("RGB"), return_tensors="pt"
                )
                out = self.blip_model.generate(**inputs, max_new_tokens=50)
                caption = self.blip_processor.decode(out[0], skip_special_tokens=True)
                self.logger.info("BLIP caption: %s", caption)

                if self.chat_feature and self.chat_feature.llm:
                    msg = self.chat_feature.llm.invoke([
                        SystemMessage(content="You are a helpful assistant that extracts descriptive tags from image captions."),
                        HumanMessage(content=f"Based on this image caption: \"{caption}\"\nSelect 2 to 10 descriptive words from it as tags. Only output the comma separated tags wrapped by <tags></tags>. Do not include any other text.")
                    ])
                    m = re.search(r"<tags>(.*?)</tags>", msg.content, re.DOTALL)
                    return m.group(1).strip() if m else msg.content.strip()
                return caption

            return "Vision model not available for tagging."
        except Exception as e:
            self.logger.error("Image tagging failed: %s", e)
            return f"Failed to tag image: {str(e)}"

    def explain_image(self, image_path: str) -> str:
        try:
            if not os.path.exists(image_path):
                return f"File '{image_path}' not found."

            if not self.vision_model and self.blip_processor and self.blip_model:
                inputs = self.blip_processor(
                    Image.open(image_path).convert("RGB"), return_tensors="pt"
                )
                out = self.blip_model.generate(**inputs, max_new_tokens=50)
                return self.blip_processor.decode(out[0], skip_special_tokens=True)

            if not self.vision_model:
                return "No vision model available."

            with open(image_path, "rb") as f:
                encoded = base64.b64encode(f.read()).decode("utf-8")

            msg = self.vision_model.invoke([
                HumanMessage(content=[
                    {"type": "text", "text": "Describe this image in detail."},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{encoded}"}},
                ])
            ])
            return msg.content if hasattr(msg, "content") else str(msg)
        except Exception as e:
            self.logger.error("Image explanation failed: %s", e)
            return f"Failed to process image: {str(e)}"
