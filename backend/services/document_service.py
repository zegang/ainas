import logging
from pypdf import PdfReader
from docx import Document as DocxDocument

logger = logging.getLogger(__name__)

def extract_text_from_pdf(file_path: str) -> str:
    """Extracts text content from a PDF file."""
    try:
        reader = PdfReader(file_path)
        text = ""
        for page in reader.pages:
            content = page.extract_text()
            if content:
                text += content + "\n"
        return text.strip()
    except Exception as e:
        logger.error(f"Error parsing PDF {file_path}: {e}")
        return ""

def extract_text_from_docx(file_path: str) -> str:
    """Extracts text content from a DOCX file."""
    try:
        doc = DocxDocument(file_path)
        text = "\n".join([paragraph.text for paragraph in doc.paragraphs])
        return text.strip()
    except Exception as e:
        logger.error(f"Error parsing DOCX {file_path}: {e}")
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
            logger.warning(f"Could not read text file {file_path}: {e}")
    return ""