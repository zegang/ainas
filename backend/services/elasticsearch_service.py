import logging
from typing import List, Optional, Dict, Any
from elasticsearch import AsyncElasticsearch
from backend.core import config

logger = logging.getLogger(__name__)

class ElasticsearchService:
    def __init__(self):
        self.client = AsyncElasticsearch(config.ES_URL)
        self.index_name = config.ES_INDEX

    async def create_index(self):
        """Creates the nas_files index with appropriate mappings for RAG and Vector search."""
        try:
            exists = await self.client.indices.exists(index=self.index_name)
            if not exists:
                mapping = {
                    "mappings": {
                        "properties": {
                            "filename": {"type": "keyword"},
                            "path": {"type": "keyword"},
                            "content": {"type": "text"},
                            "tags": {"type": "keyword"},
                            "vector_embedding": {
                                "type": "dense_vector",
                                "dims": config.ES_EMBEDDING_DIMS,
                                "index": True,
                                "similarity": "cosine"
                            },
                            "created_at": {"type": "date"}
                        }
                    }
                }
                await self.client.indices.create(index=self.index_name, body=mapping)
                logger.info(f"Elasticsearch index '{self.index_name}' created successfully.")
            else:
                logger.info(f"Elasticsearch index '{self.index_name}' verified.")
        except Exception as e:
            logger.error(f"Failed to create Elasticsearch index: {e}")

    async def index_file(self, filename: str, path: str, tags: List[str], content: str = "", embedding: Optional[List[float]] = None):
        """Indexes file metadata and optional vector embeddings."""
        doc = {
            "filename": filename,
            "path": path,
            "tags": tags,
            "content": content,
            "created_at": "now"
        }
        if embedding:
            doc["vector_embedding"] = embedding
        
        try:
            await self.client.index(index=self.index_name, document=doc)
            logger.info(f"File '{filename}' indexed in Elasticsearch.")
        except Exception as e:
            logger.error(f"Failed to index file in Elasticsearch: {e}")

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
            logger.error(f"Elasticsearch hybrid search failed: {e}")
            return []

    async def close(self):
        await self.client.close()