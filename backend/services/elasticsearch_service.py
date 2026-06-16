import logging
from typing import List, Optional, Dict, Any
from elasticsearch import AsyncElasticsearch
from backend.core import config

class ElasticsearchService:
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        # Ensure URL is clean and uses IPv4 to avoid resolution issues.
        es_url = config.AINAS_ES_URL.strip().rstrip("/").replace("localhost", "127.0.0.1")
        self.client = AsyncElasticsearch(
            es_url,
            meta_header=False,
            request_timeout=30
        )
        self.index_name = config.AINAS_ES_INDEX

    async def create_index(self):
        """Creates the nas_files index with appropriate mappings for RAG and Vector search."""
        try:
            self.logger.info(f"Verifying existence of index '{self.index_name}'...")
            exists = await self.client.indices.exists(index=self.index_name)

            if not exists:
                self.logger.info(f"Creating Elasticsearch index '{self.index_name}'...")
                mappings = {
                    "properties": {
                        "filename": {"type": "keyword"},
                        "path": {"type": "keyword"},
                        "content": {"type": "text"},
                        "tags": {"type": "keyword"},
                        "vector_embedding": {
                            "type": "dense_vector",
                            "dims": config.AINAS_ES_EMBEDDING_DIMS,
                            "index": True,
                            "similarity": "cosine"
                        },
                        "created_at": {"type": "date"}
                    }
                }
                await self.client.indices.create(index=self.index_name, mappings=mappings)
                self.logger.info(f"Elasticsearch index '{self.index_name}' created successfully.")
            else:
                self.logger.info(f"Elasticsearch index '{self.index_name}' verified.")
        except Exception as e:
            self.logger.error(f"Failed to create Elasticsearch index: {e}")

    async def index_file(self, filename: str, path: str, tags: List[str],
                         content: str = "", embedding: Optional[List[float]] = None,
                         created_at = None, updated_at = None):
        """Indexes file metadata and optional vector embeddings."""
        from datetime import datetime
        now = datetime.now().isoformat()
        doc = {
            "filename": filename,
            "path": path,
            "tags": tags,
            "content": content,
            "created_at": created_at or now,
            "updated_at": updated_at or now
        }
        if embedding:
            doc["vector_embedding"] = embedding
        
        try:
            await self.client.index(index=self.index_name, document=doc)
            self.logger.info(f"File '{filename}' indexed in Elasticsearch.")
        except Exception as e:
            self.logger.error(f"Failed to index file in Elasticsearch: {e}")

    async def get_index_summary(self) -> Dict[str, Any]:
        """Returns a summary of all indexed documents including total count and a sample of files."""
        try:
            # Get total document count
            count_resp = await self.client.count(index=self.index_name)
            total = count_resp.get("count", 0)

            # Get document metadata for a summary list (limit to 50 for the agent)
            search_resp = await self.client.search(
                index=self.index_name,
                body={
                    "_source": ["filename", "path", "tags"],
                    "query": {"match_all": {}}
                },
                size=50
            )
            docs = [hit["_source"] for hit in search_resp["hits"]["hits"]]
            return {"total_documents": total, "documents": docs}
        except Exception as e:
            self.logger.error(f"Failed to get index summary: {e}")
            return {"error": str(e)}

    async def check_file_exists(self, path: str) -> bool:
        """Checks if a file with the given relative path is already indexed."""
        search_query = {
            "query": {
                "term": {
                    "path": path
                }
            }
        }
        try:
            response = await self.client.search(index=self.index_name, body=search_query, size=0)
            return response["hits"]["total"]["value"] > 0
        except Exception as e:
            self.logger.error(f"Failed to check file existence in Elasticsearch: {e}")
            return False

    async def delete_document(self, path: str) -> int:
        """
        Deletes documents from the index based on their relative path.
        Returns the number of documents deleted.
        """
        try:
            response = await self.client.delete_by_query(
                index=self.index_name,
                body={
                    "query": {
                        "term": {"path": path}
                    }
                },
                refresh=True
            )
            return response.get("deleted", 0)
        except Exception as e:
            self.logger.error(f"Failed to delete document from Elasticsearch: {e}")
            return 0

    async def hybrid_search(self, query_text: str, query_vector: Optional[List[float]] = None, top_k: int = 5) -> List[Dict[str, Any]]:
        """
        Performs a hybrid search combining BM25 keyword matching and kNN vector similarity.
        """
        search_query = {
            "query": {
                "multi_match": {
                    "query": query_text,
                    "fields": ["filename^2", "content", "tags^1.5"]
                }
            }
        }

        if query_vector:
            search_query["knn"] = {
                "field": "vector_embedding",
                "query_vector": query_vector,
                "k": top_k,
                "num_candidates": 100
            }

        try:
            response = await self.client.search(index=self.index_name, body=search_query, size=top_k)
            return [hit["_source"] for hit in response["hits"]["hits"]]
        except Exception as e:
            self.logger.error(f"Elasticsearch hybrid search failed: {e}")
            return []

    async def close(self):
        await self.client.close()