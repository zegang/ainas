import logging
from typing import List
from pypdf import PdfReader
from docx import Document as DocxDocument

def extract_text_from_pdf(file_path: str) -> str:
    """Extracts text content from a PDF file."""
    try:
        logger = logging.getLogger(__name__)
        reader = PdfReader(file_path)
        text = ""
        for page in reader.pages:
            content = page.extract_text()
            if content:
                text += content + "\n"
        return text.strip()
    except Exception as e:
        logging.getLogger(__name__).error(f"Error parsing PDF {file_path}: {e}")
        return ""

def extract_text_from_docx(file_path: str) -> str:
    """Extracts text content from a DOCX file."""
    try:
        logger = logging.getLogger(__name__)
        doc = DocxDocument(file_path)
        text = "\n".join([paragraph.text for paragraph in doc.paragraphs])
        return text.strip()
    except Exception as e:
        logging.getLogger(__name__).error(f"Error parsing DOCX {file_path}: {e}")
        return ""

def extract_text(file_path: str) -> str:
    """Dispatches text extraction based on file extension."""
    ext = file_path.lower()
    if ext.endswith('.pdf'):
        return extract_text_from_pdf(file_path)
    elif ext.endswith('.docx'):
        return extract_text_from_docx(file_path)
    elif ext.endswith(('.txt', '.md', '.log')):
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                return f.read()
        except Exception as e:
            logging.getLogger(__name__).warning(f"Could not read text file {file_path}: {e}")
    return ""


_CHUNK_SIZE = 2000
_CHUNK_OVERLAP = 256


def chunk_text(text: str, max_chars: int = _CHUNK_SIZE, overlap_chars: int = _CHUNK_OVERLAP) -> List[str]:
    """Splits text into overlapping chunks of roughly ``max_chars`` characters.

    Each chunk tries to break at a word boundary.  Overlap prevents information
    loss across chunk boundaries during retrieval.
    """
    if not text or len(text) <= max_chars:
        return [text] if text else []

    chunks = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        # Retreat to the last space boundary when we aren't at the tail
        if end < len(text):
            last_space = text.rfind(' ', start, end)
            if last_space > start:
                end = last_space
        chunks.append(text[start:end].strip())
        if end == len(text):
            break
        start = end - overlap_chars
    return chunks