import io
import os
import logging
from PIL import Image

def create_thumbnail(source_path: str, dest_path: str, size=(200, 200)):
    """
    Generates a thumbnail for the image at source_path and saves it to dest_path.
    """
    logger = logging.getLogger(__name__)
    try:
        with Image.open(source_path) as img:
            img.thumbnail(size)
            img.save(dest_path)
        logger.info(f"Thumbnail successfully created at {dest_path}")
    except Exception as e:
        logger.error(f"Failed to create thumbnail for {source_path}: {e}")
        raise e

def pdf_to_images(source_path: str, output_dir: str, quality: int = 95) -> list[dict]:
    """Render every page of a PDF as a PNG image saved to output_dir.
    Returns a list of {page, filename, path} dicts."""
    logger = logging.getLogger(__name__)
    try:
        import pypdfium2 as pdfium
    except ImportError:
        raise RuntimeError("pypdfium2 is required for PDF-to-image conversion")

    os.makedirs(output_dir, exist_ok=True)
    pdf = pdfium.PdfDocument(source_path)
    pages = len(pdf)
    results = []
    base = os.path.splitext(os.path.basename(source_path))[0]

    for i in range(pages):
        page = pdf[i]
        bitmap = page.render(scale=2.0)
        pil_image = bitmap.to_pil()
        fname = f"{base}_page_{i + 1:03d}.png"
        dest = os.path.join(output_dir, fname)
        pil_image.convert("RGB").save(dest, quality=quality)
        results.append({"page": i + 1, "filename": fname, "path": dest})
        logger.info("Rendered page %d/%d -> %s", i + 1, pages, dest)

    return results


def create_pdf_thumbnail(source_path: str, dest_path: str, size=(200, 200)):
    """
    Generates a thumbnail from the first page of a PDF file.
    Requires pypdf with image extraction support (Pillow).
    Falls back to a blank placeholder if rendering fails.
    """
    logger = logging.getLogger(__name__)
    try:
        # Try pypdfium2 first (best quality, renders actual page)
        try:
            import pypdfium2 as pdfium
            pdf = pdfium.PdfDocument(source_path)
            page = pdf[0]
            bitmap = page.render(scale=1.5)
            pil_image = bitmap.to_pil()
            pil_image.thumbnail(size)
            # Ensure destination parent directories exist
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            # Save as JPEG thumbnail (same convention as image thumbnails)
            thumb_dest = dest_path if dest_path.lower().endswith(('.jpg', '.jpeg', '.png')) else dest_path + ".jpg"
            pil_image.convert("RGB").save(thumb_dest)
            logger.info(f"PDF thumbnail (pypdfium2) created at {thumb_dest}")
            return
        except ImportError:
            pass

        # Fallback: extract the first embedded image from the PDF via pypdf
        from pypdf import PdfReader
        reader = PdfReader(source_path)
        if not reader.pages:
            raise ValueError("PDF has no pages")

        images = list(reader.pages[0].images)
        if images:
            img_data = images[0].data
            with Image.open(io.BytesIO(img_data)) as img:
                img.thumbnail(size)
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                thumb_dest = dest_path if dest_path.lower().endswith(('.jpg', '.jpeg', '.png')) else dest_path + ".jpg"
                img.convert("RGB").save(thumb_dest)
            logger.info(f"PDF thumbnail (embedded image) created at {thumb_dest}")
        else:
            # Last resort: create a simple placeholder icon
            placeholder = Image.new("RGB", size, color=(230, 230, 230))
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            thumb_dest = dest_path if dest_path.lower().endswith(('.jpg', '.jpeg', '.png')) else dest_path + ".jpg"
            placeholder.save(thumb_dest)
            logger.warning(f"No images in PDF first page, saved placeholder thumbnail at {thumb_dest}")

    except Exception as e:
        logger.error(f"Failed to create PDF thumbnail for {source_path}: {e}")
        raise e