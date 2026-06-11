import os
from pathlib import Path
from langchain_core.tools import tool
from backend.services.system_service import get_disk_usage

def get_file_tools(storage_path: str):
    """
    Returns a list of tools for file system operations on the NAS.
    """
    abs_storage = os.path.abspath(storage_path)
    
    @tool
    def list_files(path: str = "") -> str:
        """
        Lists files and directories in the specified path on the NAS.
        The path is relative to the NAS storage root (e.g., 'photos/2023'). 
        Use an empty string to list the root directory.
        """
        try:
            rel_path = path.strip().strip("'\"").strip().lstrip("/")
            # Use Path for safer resolution
            full_path = Path(abs_storage).joinpath(rel_path).resolve()
            
            # Security check: ensure we stay within storage root
            if not str(full_path).startswith(abs_storage):
                return "Error: Access denied. Cannot access paths outside of the storage root."

            if not os.path.exists(full_path):
                return f"Error: Path '{path}' does not exist."
            
            if not os.path.isdir(full_path):
                return f"Error: '{path}' is a file. Use this tool only for directories."

            items = os.listdir(full_path)
            if not items:
                return f"The directory '{path}' is empty."
            
            lines = []
            for item in items:
                item_path = os.path.join(full_path, item)
                is_dir = os.path.isdir(item_path)
                lines.append(f"{'[DIR] ' if is_dir else '      '}{item}")
            
            return f"Contents of '{path if path else '/' }':\n" + "\n".join(lines)
        except Exception as e:
            return f"Error listing files: {str(e)}"

    @tool
    def search_files(query: str, path: str = "") -> str:
        """
        Recursively searches for files and directories matching the query name.
        Starts searching from the specified path (relative to root).
        Returns relative paths of the matching items.
        """
        try:
            rel_path = path.strip().strip("'\"").strip().lstrip("/")
            start_path = os.path.normpath(os.path.join(abs_storage, rel_path))
            
            if not start_path.startswith(abs_storage):
                return "Error: Access denied. Cannot access paths outside of the storage root."

            if not os.path.exists(start_path):
                return f"Error: Path '{path}' does not exist."
            
            matches = []
            for root, _, files in os.walk(start_path):
                for name in files:
                    if query.lower() in name.lower():
                        match_path = os.path.join(root, name)
                        matches.append(os.path.relpath(match_path, abs_storage))
            
            if not matches:
                return f"No items found matching '{query}' in '{path if path else '/' }'."
            
            # Limit output length to manage token usage
            limit = 25
            result = f"Found {len(matches)} matching items:\n"
            result += "\n".join(matches[:limit])
            if len(matches) > limit:
                result += f"\n... and {len(matches) - limit} more."
            return result
        except Exception as e:
            return f"Error searching files: {str(e)}"

    @tool
    def get_storage_status() -> str:
        """
        Returns the current disk usage and availability of the NAS storage.
        Use this to check if there is enough space or to monitor system health.
        """
        usage = get_disk_usage()
        if not usage:
            return "Error retrieving storage status."
        
        status = "CRITICAL" if usage["is_critical"] else "Normal"
        return (f"Storage Status: {status}\n"
                f"Used: {usage['used_gb']} GB / {usage['total_gb']} GB ({usage['percent_used']}%)\n"
                f"Free: {usage['free_gb']} GB")

    return [list_files, search_files, get_storage_status]