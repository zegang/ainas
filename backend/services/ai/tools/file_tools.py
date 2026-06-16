import os
from pathlib import Path
from langchain_core.tools import tool
from backend.services.system_service import get_disk_usage

def get_file_tools(storage_path: str, es_service=None, embeddings=None):
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

    @tool
    async def query_documents(query: str) -> str:
        """
        Searches the content of indexed documents (PDF, DOCX, TXT, MD, LOG) using semantic and keyword search.
        Use this to answer questions about document content or to find specific information within files.
        """
        if not es_service:
            return "Error: Document search is not enabled (Elasticsearch missing)."

        try:
            # Generate embedding for vector search if the embedding model is provided
            query_vector = None
            if embeddings:
                # Use aembed_query for async execution
                query_vector = await embeddings.aembed_query(query)

            # Perform hybrid search (BM25 + kNN) via the Elasticsearch service
            hits = await es_service.hybrid_search(query_text=query, query_vector=query_vector, top_k=5)

            if not hits:
                return "No matching documents or relevant content found in the index."

            response_parts = ["Found relevant content in the following documents:"]
            for hit in hits:
                filename = hit.get("filename", "unknown")
                path = hit.get("path", "unknown")
                content = hit.get("content", "")
                # Truncate content for the LLM context window to save tokens
                snippet = content[:800].replace("\n", " ") + "..." if len(content) > 800 else content
                response_parts.append(f"- {filename} ({path}): \"{snippet}\"")

            return "\n\n".join(response_parts)
        except Exception as e:
            return f"Failed to query documents: {str(e)}"

    @tool
    async def summarize_indexed_documents() -> str:
        """
        Provides a summary of all documents currently indexed in the RAG system (Elasticsearch).
        Returns the total count and a list of filenames. 
        Use this to see what files the AI has 'read' and can answer questions about.
        """
        if not es_service:
            return "Error: Document search service is not available."

        try:
            summary = await es_service.get_index_summary()
            if "error" in summary:
                return f"Error retrieving summary: {summary['error']}"

            total = summary["total_documents"]
            docs = summary["documents"]

            if total == 0:
                return "The search index is currently empty. No documents have been indexed yet."

            result = f"The AI has indexed a total of {total} documents.\n\n"
            result += "Recently indexed files:\n"
            for doc in docs[:15]:  # Show a concise list of 15
                result += f"- {doc['filename']} (Path: {doc['path']})\n"
            
            if total > 15:
                result += f"\n... and {total - 15} more items."
            return result
        except Exception as e:
            return f"Failed to summarize indexed documents: {str(e)}"

    @tool
    async def delete_indexed_document(path: str) -> str:
        """
        Removes a specific document from the AI's search index (Elasticsearch).
        Use this when a file is physically deleted or should be forgotten by the RAG system.
        The path must be the exact relative path as stored in the index (e.g., 'folder/report.pdf').
        """
        if not es_service:
            return "Error: Document search service (Elasticsearch) is not available."

        try:
            deleted_count = await es_service.delete_document(path)
            if deleted_count > 0:
                return f"Successfully deleted '{path}' from the search index ({deleted_count} entries removed)."
            else:
                return f"Document with path '{path}' was not found in the search index."
        except Exception as e:
            return f"Error during document deletion from index: {str(e)}"

    return [list_files, search_files, get_storage_status, query_documents, summarize_indexed_documents, delete_indexed_document]