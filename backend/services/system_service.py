import shutil
import logging
from backend.core import config

def get_disk_usage():
    """
    Calculates disk usage for the storage path configured in the NAS.
    Returns a dictionary with usage statistics and a criticality flag.
    """
    logger = logging.getLogger(__name__)
    try:
        total, used, free = shutil.disk_usage(config.AINAS_DATA_PATH)
        percent_used = (used / total) * 100
        return {
            "total_gb": round(total / (1024**3), 2),
            "used_gb": round(used / (1024**3), 2),
            "free_gb": round(free / (1024**3), 2),
            "percent_used": round(percent_used, 2),
            "is_critical": percent_used >= config.AINAS_DISK_USAGE_THRESHOLD_PCT
        }
    except Exception as e:
        logging.getLogger(__name__).error(f"Failed to calculate disk usage: {e}")
        return None

def check_disk_and_alert():
    """Checks disk usage and logs an alert if it exceeds the critical threshold."""
    usage = get_disk_usage()
    if usage and usage["is_critical"]:
        logging.getLogger(__name__).warning(
            f"CRITICAL DISK ALERT: {usage['percent_used']}% used on {config.AINAS_DATA_PATH}"
        )
    return usage