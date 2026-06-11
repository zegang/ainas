import os
import logging
from PIL import Image

logger = logging.getLogger(__name__)

def create_thumbnail(source_path: str, dest_path: str, size=(200, 200)):
    """
    Generates a thumbnail for the image at source_path and saves it to dest_path.
    """
    try:
        with Image.open(source_path) as img:
            img.thumbnail(size)
            img.save(dest_path)
        logger.info(f"Thumbnail successfully created at {dest_path}")
    except Exception as e:
        logger.error(f"Failed to create thumbnail for {source_path}: {e}")
        raise e