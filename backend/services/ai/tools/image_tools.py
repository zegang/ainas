import logging
import os
import base64
import requests
from typing import List
from PIL import Image
from openai import OpenAI
from langchain_core.tools import tool
from langchain_core.messages import HumanMessage # type: ignore
from backend.core import config


def get_image_tools(storage_path: str, api_key: str, vision_model=None, projector_path=None, **kwargs):
    logger = logging.getLogger(__name__)

    @tool
    def tag_image(file_name: str) -> str:
        """Generates descriptive labels/tags for an image file using computer vision.
        Pass the FULL and EXACT filename (e.g., 'Screenshot from 2024-01-01.png')."""
        try:
            file_name = file_name.strip().strip("'\"").strip()
            full_path = os.path.join(storage_path, file_name)
            logger.info("Tagging image: %s", full_path)
            if not os.path.exists(full_path):
                return f"File '{file_name}' not found."
            
            # Use pre-loaded BLIP model if vision_model (LangChain LLM) is not available
            if not vision_model and kwargs.get('blip_processor') and kwargs.get('blip_model'):
                processor = kwargs['blip_processor']
                model = kwargs['blip_model']
                inputs = processor(Image.open(full_path).convert("RGB"), return_tensors="pt") # type: ignore
                out = model.generate(**inputs, max_new_tokens=50) # type: ignore
                return processor.decode(out[0], skip_special_tokens=True) # type: ignore
            llm = vision_model

            with open(full_path, "rb") as f:
                encoded = base64.b64encode(f.read()).decode("utf-8")
                
            msg = llm.invoke([
                HumanMessage(content=[
                    {"type": "text", "text": "Generate a comma-separated list of 5-10 descriptive tags for this image."},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{encoded}"}}
                ])
            ])
            logger.info("Tags generated: %s", msg.content)
            return msg.content
        except Exception as e:
            return f"Failed to tag image: {str(e)}"

    @tool
    def explain_image(file_name: str) -> str:
        """Explains or describes the content of an existing image file stored on the NAS.
        Use this when asked to describe, analyze, or 'generate content' describing what is in a specific image.
        Pass the FULL and EXACT filename (e.g., 'Screenshot from 2024-01-01.png')."""
        try:
            file_name = file_name.strip().strip("'\"").strip()
            full_path = os.path.join(storage_path, file_name)
            logger.info("Explaining image: %s", full_path)
            
            if not vision_model and kwargs.get('blip_processor') and kwargs.get('blip_model'):
                processor = kwargs['blip_processor']
                model = kwargs['blip_model']
                inputs = processor(Image.open(full_path).convert("RGB"), return_tensors="pt") # type: ignore
                out = model.generate(**inputs, max_new_tokens=50) # type: ignore
                return processor.decode(out[0], skip_special_tokens=True) # type: ignore

            with open(full_path, "rb") as f:
                encoded = base64.b64encode(f.read()).decode("utf-8")
            
            llm = vision_model

            msg = llm.invoke([
                HumanMessage(content=[
                    {"type": "text", "text": "Describe this image in detail."},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{encoded}"}}
                ])
            ])
            logger.info("Explanation generated: %s", msg.content)
            return msg.content
        except Exception as e:
            return f"Failed to process image: {str(e)}"

    @tool
    def generate_image(prompt: str, output_name: str = "generated_ai.png") -> str:
        """Generates a BRAND NEW image from a text description (text-to-image) and saves it to the NAS.
        Do NOT use this tool for existing images or to describe/analyze images."""
        return f"Not supported yet."
        output_name = output_name.strip().strip("'\"").strip()
        try:
            client = OpenAI(api_key=api_key)
            response = client.images.generate(model="dall-e-3", prompt=prompt, n=1, size="1024x1024")
            img_data = requests.get(response.data[0].url).content
            with open(os.path.join(storage_path, output_name), "wb") as f:
                f.write(img_data)
            return f"Successfully generated image and saved as {output_name}"
        except Exception as e:
            return f"Image generation failed: {str(e)}"

    @tool
    def create_image_dashboard(files: List[str], output_name: str = "dashboard.png") -> str:
        """Combines multiple images into a single grid dashboard image."""
        try:
            imgs = [Image.open(os.path.join(storage_path, f.strip().strip("'\"").strip())) for f in files]
            logger.info("Creating dashboard with %d images", len(imgs))
            if not imgs: return "No images found."
            # Simple 2-column grid
            w, h = imgs[0].size
            canvas = Image.new('RGB', (w * 2, h * ((len(imgs) + 1) // 2)))
            for i, img in enumerate(imgs):
                canvas.paste(img.resize((w, h)), ((i % 2) * w, (i // 2) * h))
            canvas.save(os.path.join(storage_path, output_name))
            logger.info("Dashboard saved as %s", output_name)
            return f"Dashboard created: {output_name}"
        except Exception as e:
            return f"Dashboard creation failed: {str(e)}"

    return [tag_image, explain_image, generate_image, create_image_dashboard]