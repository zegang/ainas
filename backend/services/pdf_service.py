import io
import os
import logging
from PIL import Image
from pypdf import PdfWriter


def merge_to_pdf(file_paths: list[str], output_path: str) -> str:
    """Merge multiple files (images and/or PDFs) into a single PDF.
    Images are converted to PDF pages; PDFs are appended page by page.
    Returns the output path."""
    logger = logging.getLogger(__name__)
    writer = PdfWriter()
    image_extensions = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'}
    processed = 0
    try:
        for path in file_paths:
            lower = path.lower()
            if lower.endswith('.pdf'):
                writer.append(path)
                processed += 1
            elif any(lower.endswith(ext) for ext in image_extensions):
                img = Image.open(path)
                img_rgb = img.convert('RGB')
                buf = io.BytesIO()
                img_rgb.save(buf, format='PDF')
                buf.seek(0)
                writer.append(buf)
                img.close()
                processed += 1
            else:
                logger.warning("Skipping unsupported file: %s", path)

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        writer.write(output_path)
        logger.info("Merged %d file(s) into %s", processed, output_path)
        return output_path
    except Exception as e:
        logger.error("Failed to merge files into PDF: %s", e)
        raise
    finally:
        writer.close()
