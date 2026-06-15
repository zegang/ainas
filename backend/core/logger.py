import logging
import os
from backend.core import config

def setup_logging():
    """
    Configures the logging system for the application using settings from the global config.
    """
    log_format = "%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s"
    log_file = config.AINAS_LOG_FILE
    
    # Ensure the directory for the log file exists
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    
    # Determine logging level from config
    log_level = getattr(logging, config.AINAS_LOG_LEVEL, logging.INFO)

    logging.basicConfig(
        level=log_level,
        format=log_format,
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler()
        ],
        force=True
    )