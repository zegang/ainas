import asyncio
import logging
import os
from datetime import datetime
from typing import List, Optional, Dict, Any
from elasticsearch import AsyncElasticsearch
from backend.core import config
from backend.services.document_service import extract_text, chunk_text

# ── Terminology ──────────────────────────────────────────────────────────
#   File      – an original uploaded document (e.g. report.pdf).  One file
#               produces many chunks.
#   Chunk     – a contiguous segment of the file's text (~2000 chars with
#               256-char overlap).  Chunking keeps each piece small enough
#               for embedding context windows and makes retrieval more
#               precise (a single ES doc can answer a specific question).
#   Document  – a single Elasticsearch indexed entry.  Each chunk becomes
#               one ES document.  So 1 file = N chunks = N ES documents.
#               All documents for the same file share the same ``path``
#               field, differentiated by ``chunk_index``.
# ─────────────────────────────────────────────────────────────────────────

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

    def _build_mappings(self) -> dict:
        # Each ES document is one chunk.  ``path`` groups all chunks of
        # one file; ``chunk_index`` orders them.
        return {
            "properties": {
                "filename": {"type": "keyword"},
                "path": {"type": "keyword"},
                "content": {"type": "text"},
                "tags": {"type": "keyword"},
                "chunk_index": {"type": "integer"},
                "vector_embedding": {
                    "type": "dense_vector",
                    "dims": config.AINAS_ES_EMBEDDING_DIMS,
                    "index": True,
                    "similarity": "cosine"
                },
                "created_at": {"type": "date"}
            }
        }

    async def _update_mapping_if_needed(self):
        """Checks and fixes mapping drift (e.g. vector dimensions mismatch)."""
        try:
            current = await self.client.indices.get_mapping(index=self.index_name)
            props = current.get(self.index_name, {}).get("mappings", {}).get("properties", {})

            needs_recreate = False
            vec = props.get("vector_embedding", {})
            if vec.get("dims") != config.AINAS_ES_EMBEDDING_DIMS:
                self.logger.warning(
                    "Vector dimension mismatch: mapping has %s, config wants %s. Recreating index.",
                    vec.get("dims"), config.AINAS_ES_EMBEDDING_DIMS,
                )
                needs_recreate = True

            if "chunk_index" not in props:
                self.logger.info("Adding chunk_index field to existing index mapping.")
                await self.client.indices.put_mapping(
                    index=self.index_name,
                    properties={"chunk_index": {"type": "integer"}}
                )

            if needs_recreate:
                await self.client.indices.delete(index=self.index_name)
                mappings = self._build_mappings()
                await self.client.indices.create(index=self.index_name, mappings=mappings)
                self.logger.info("Elasticsearch index '%s' recreated with updated mapping.", self.index_name)
        except Exception as e:
            self.logger.warning("Could not update index mapping (non-critical): %s", e)

    async def create_index(self):
        """Creates the nas_files index with appropriate mappings for RAG and Vector search."""
        try:
            self.logger.info(f"Verifying existence of index '{self.index_name}'...")
            exists = await self.client.indices.exists(index=self.index_name)

            if not exists:
                self.logger.info(f"Creating Elasticsearch index '{self.index_name}'...")
                mappings = self._build_mappings()
                await self.client.indices.create(index=self.index_name, mappings=mappings)
                self.logger.info(f"Elasticsearch index '{self.index_name}' created successfully.")
            else:
                self.logger.info(f"Elasticsearch index '{self.index_name}' verified.")
                await self._update_mapping_if_needed()
        except Exception as e:
            self.logger.error(f"Failed to create Elasticsearch index: {e}")

    # ── index_chunk ──────────────────────────────────────────────────────
    # Writes ONE Elasticsearch document representing a single chunk of a
    # larger file.  Every chunk for the same file carries the same ``path``
    # and ``filename`` but a unique ``chunk_index``.
    # ─────────────────────────────────────────────────────────────────────
    async def _index_chunk(self, filename: str, path: str, tags: List[str],
                         content: str = "", embedding: Optional[List[float]] = None,
                         chunk_index: int = 0,
                         created_at = None, updated_at = None):
        """Indexes a file chunk with its metadata and vector embedding."""
        now = datetime.now().isoformat()
        doc = {
            "filename": filename,
            "path": path,
            "tags": tags,
            "content": content,
            "chunk_index": chunk_index,
            "created_at": created_at or now,
            "updated_at": updated_at or now
        }
        if embedding:
            doc["vector_embedding"] = embedding
        
        try:
            await self.client.index(index=self.index_name, document=doc)
            self.logger.info(f"File '{filename}' chunk {chunk_index} indexed in Elasticsearch.")
        except Exception as e:
            self.logger.error(f"Failed to index file in Elasticsearch: {e}")

    # ── get_index_summary ────────────────────────────────────────────────
    # Returns two counts and a grouped file list:
    #   total_chunks – every ES document (each chunk of every file).
    #   files        – one entry per unique ``path``, with its ``chunk_count``.
    # The ES ``terms`` aggregation on the ``path`` field collapses all
    # chunk-documents back into file-level entries for display.
    # ─────────────────────────────────────────────────────────────────────
    async def get_index_summary(self) -> Dict[str, Any]:
        """Returns a summary of all indexed documents, grouped by file path."""
        try:
            count_resp = await self.client.count(index=self.index_name)
            total_chunks = count_resp.get("count", 0)

            search_resp = await self.client.search(
                index=self.index_name,
                body={
                    "size": 0,
                    "aggs": {
                        "by_path": {
                            "terms": {
                                "field": "path",
                                "size": 50,
                                "order": {"_count": "desc"}
                            },
                            "aggs": {
                                "top_hit": {
                                    "top_hits": {
                                        "size": 1,
                                        "_source": ["filename"]
                                    }
                                }
                            }
                        }
                    }
                }
            )

            buckets = search_resp.get("aggregations", {}).get("by_path", {}).get("buckets", [])
            files = []
            for bucket in buckets:
                hits = bucket.get("top_hit", {}).get("hits", {}).get("hits", [])
                filename = hits[0]["_source"]["filename"] if hits else bucket["key"]
                files.append({
                    "filename": filename,
                    "path": bucket["key"],
                    "chunk_count": bucket["doc_count"],
                })

            return {
                "total_chunks": total_chunks,
                "total_files": len(files),
                "files": files,
            }
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

    # ── delete_file ──────────────────────────────────────────────────────
    # Deletes ALL ES documents (every chunk) sharing the given file path.
    # This is a file-level operation — even though it deletes many
    # documents, the caller thinks in terms of one file.
    # ─────────────────────────────────────────────────────────────────────
    async def delete_file(self, path: str) -> int:
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

    async def delete_files_by_prefix(self, path_prefix: str) -> int:
        """
        Deletes documents from the index whose ``path`` starts with the given prefix.
        Returns the number of documents deleted.
        """
        try:
            response = await self.client.delete_by_query(
                index=self.index_name,
                body={
                    "query": {
                        "prefix": {"path": path_prefix}
                    }
                },
                refresh=True,
            )
            return response.get("deleted", 0)
        except Exception as e:
            self.logger.error(f"Failed to delete documents by prefix from Elasticsearch: {e}")
            return 0

    # ── index_file ───────────────────────────────────────────────────────
    # High-level entry point: accepts one **file**, extracts its text,
    # splits into **chunks**, and writes one ES **document** per chunk.
    # The naming reflects the pipeline:  file → chunks → documents.
    # ─────────────────────────────────────────────────────────────────────
    async def index_file(self, file_path: str, rel_path: str, filename: str,
                              tags: List[str],
                              embeddings=None,
                              created_at: Optional[str] = None,
                              updated_at: Optional[str] = None) -> bool:
        """Extracts text, chunks, embeds, and indexes a document into Elasticsearch.

        This is the high-level entry point for RAG indexing.  It handles:

          1. Text extraction (PDF / DOCX / TXT / MD / LOG)
          2. Chunking into ~500-token segments with overlap
          3. Deleting stale ES entries for the same path
          4. Generating vector embeddings per chunk
          5. Indexing each chunk with retry-on-failure

        Returns ``True`` if at least one chunk was indexed, ``False`` otherwise.
        """
        logger = logging.getLogger(__name__)

        is_supported = filename.lower().endswith(('.pdf', '.docx', '.txt', '.md', '.log'))
        if not is_supported:
            logger.info("Skipping ES indexing for %s (unsupported type)", filename)
            return False

        content = await asyncio.to_thread(extract_text, file_path)
        if not content:
            logger.info("Skipping ES indexing for %s (no extractable content)", rel_path)
            return False

        # Remove stale entries for this path before re-indexing
        deleted = await self.delete_file(rel_path)
        if deleted:
            logger.info("Removed %d stale ES entries for %s", deleted, rel_path)

        if created_at is None or updated_at is None:
            try:
                st = os.stat(file_path)
                created_at = datetime.fromtimestamp(st.st_ctime).isoformat()
                updated_at = datetime.fromtimestamp(st.st_mtime).isoformat()
            except OSError:
                now = datetime.now().isoformat()
                created_at = created_at or now
                updated_at = updated_at or now

        chunks = chunk_text(content)
        logger.info("Split %s into %d chunk(s) for indexing", rel_path, len(chunks))

        max_retries = 3
        indexed_any = False
        # ── Chunk → ES document loop ─────────────────────────────────────
        # Why chunk?  Embedding models have a fixed context window (~512
        # tokens for most sentence-transformers).  A 100-page PDF would
        # exceed that window and lose detail.  By splitting into chunks we:
        #   1. Stay within the embedding model's input limit.
        #   2. Keep each ES document focused on one topic/passage so that
        #      hybrid search returns precisely the relevant snippet, not
        #      a whole file that buries the answer.
        #   3. Preserve the original order via ``chunk_index`` so the
        #      caller can reconstruct context if needed.
        # ─────────────────────────────────────────────────────────────────
        for chunk_idx, chunk in enumerate(chunks):
            chunk_embedding = None
            if embeddings is not None:
                result = await embeddings.aembed_documents([chunk])
                chunk_embedding = result[0]

            for attempt in range(max_retries):
                try:
                    await self._index_chunk(
                        filename=filename, path=rel_path,
                        tags=tags, content=chunk,
                        embedding=chunk_embedding,
                        chunk_index=chunk_idx,
                        created_at=created_at, updated_at=updated_at
                    )
                    logger.info("ES indexed chunk %d/%d for %s", chunk_idx + 1, len(chunks), rel_path)
                    indexed_any = True
                    break
                except Exception as e:
                    logger.warning("ES indexing failed for %s chunk %d (attempt %d): %s",
                                   rel_path, chunk_idx, attempt + 1, e)
                    if attempt < max_retries - 1:
                        await asyncio.sleep(2 ** attempt)
                    else:
                        logger.error("ES indexing failed permanently for %s chunk %d", rel_path, chunk_idx)
        return indexed_any

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

    async def clear_index(self) -> int:
        """Deletes all documents from the index. Returns the number deleted."""
        try:
            response = await self.client.delete_by_query(
                index=self.index_name,
                body={"query": {"match_all": {}}},
                refresh=True,
            )
            deleted = response.get("deleted", 0)
            self.logger.info("Cleared %d documents from index '%s'", deleted, self.index_name)
            return deleted
        except Exception as e:
            self.logger.error("Failed to clear index '%s': %s", self.index_name, e)
            raise

    async def close(self):
        await self.client.close()