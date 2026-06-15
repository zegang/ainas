import logging
import subprocess
from langchain_core.tools import tool
from backend.services.system_service import get_disk_usage

def get_system_stats_summary() -> str:
    """Gathers CPU, RAM, Disk, and GPU utilization stats as a summary string."""
    stats = []
    logger = logging.getLogger(__name__)
    try:
        import psutil
        cpu_pct = psutil.cpu_percent(interval=None)
        mem_pct = psutil.virtual_memory().percent
        stats.append(f"CPU: {cpu_pct}%")
        stats.append(f"RAM: {mem_pct}%")
    except ImportError:
        stats.append("CPU/RAM: psutil not installed")

    # Disk usage monitoring
    usage = get_disk_usage()
    if usage:
        stats.append(f"Disk: {usage['percent_used']}%")
        if usage['is_critical']:
            stats.append("(!) DISK CRITICAL")

    # NVIDIA GPU Stats
    try:
        nvidia_res = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used", "--format=csv,noheader,nounits"],
            encoding='utf-8'
        )
        nvidia_info = nvidia_res.strip().replace("\n", " | ")
        stats.append(f"NVIDIA GPU (Util, Mem): {nvidia_info}")
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    # AMD GPU Stats
    try:
        # GPU utilization
        roc_gpu_util_res = subprocess.check_output(
            ["rocm-smi", "--showuse", "--csv"],
            encoding='utf-8'
        )
        gpu_util_pct = "N/A"
        gpu_util_lines = roc_gpu_util_res.strip().split('\n')
        if len(gpu_util_lines) > 1:
            gpu_data = gpu_util_lines[1].split(',')
            if len(gpu_data) > 9:
                gpu_util_pct = gpu_data[9].strip()

        # VRAM utilization
        roc_vram_util_res = subprocess.check_output(
            ["rocm-smi", "--showmeminfo", "VRAM", "--csv"],
            encoding='utf-8'
        )
        vram_util_pct = "N/A"
        vram_util_lines = roc_vram_util_res.strip().split('\n')
        if len(vram_util_lines) > 1:
            vram_data = vram_util_lines[1].split(',')
            if len(vram_data) > 1:
                vram_util_pct = vram_data[1].strip()

        if gpu_util_pct != "N/A" or vram_util_pct != "N/A":
            stats.append(f"AMD GPU (Util: {gpu_util_pct}, VRAM: {vram_util_pct})")
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    except Exception as e:
        logger.warning(f"Error parsing rocm-smi output: {e}")

    return " | ".join(stats)

@tool
def get_system_performance() -> str:
    """Returns the current system resource usage including CPU, RAM, Disk, and GPU utilization. 
    Use this when asked about system health, load, or hardware performance."""
    return get_system_stats_summary()

def get_system_tools():
    """Returns a list of system-related tools."""
    return [get_system_performance]