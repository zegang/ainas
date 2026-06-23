import json
import os
import shutil
import logging
import threading
import requests
from datetime import datetime
from typing import List, Dict, Any
from huggingface_hub import HfApi, hf_hub_download, snapshot_download, hf_hub_url
from huggingface_hub.utils import build_hf_headers
from huggingface_hub.errors import RepositoryNotFoundError, RevisionNotFoundError
from backend.core import config
from backend.db.database import db_manager, AiModelRecord

try:
    from gguf import GGUFReader
except ImportError:
    GGUFReader = None

logger = logging.getLogger(__name__)

class HuggingFaceService:
    """
    Service to handle Hugging Face model searching, local listing, and downloading.
    """

    _download_tasks: list[str] = []
    _tasks_lock = threading.Lock()
    _download_semaphore: threading.Semaphore | None = None

    def __init__(self):
        # Use None if token is empty string to avoid illegal "Bearer " header issues.
        # Passing an empty string results in an invalid 'Authorization: Bearer ' header.
        self.token = config.AINAS_HF_API_TOKEN if config.AINAS_HF_API_TOKEN else None
        self.api = HfApi(token=self.token)
        self.cache_dir = config.AINAS_HF_CACHE_DIR
        if HuggingFaceService._download_semaphore is None:
            HuggingFaceService._download_semaphore = threading.Semaphore(
                config.AINAS_MAX_CONCURRENT_DOWNLOADS
            )

    def _enqueue_download(self, name: str, repo_id: str, filename: str | None = None,
                          model_type: str | None = None) -> bool:
        """Add a download task to the queue. Returns True if enqueued, False if duplicate."""
        with self._tasks_lock:
            if name in self._download_tasks:
                logger.info("Download task already queued: %s, skipping", name)
                return False
            self._download_tasks.append(name)

        def _task():
            try:
                self._download_semaphore.acquire()
                logger.info("Starting download task: %s", name)
                if filename:
                    self.download(repo_id, filename)
                else:
                    self.download_snapshot(repo_id)
            except Exception:
                logger.exception("Download task failed: %s", name)
            finally:
                self._download_semaphore.release()
                with self._tasks_lock:
                    if name in self._download_tasks:
                        self._download_tasks.remove(name)

        threading.Thread(target=_task, daemon=True).start()
        return True

    @property
    def _repos_dir(self) -> str:
        return os.path.join(self.cache_dir, "repos")

    def _repo_folder(self, repo_id: str) -> str:
        return os.path.join(self._repos_dir, "models--" + repo_id.replace("/", "--"))

    def _fetch_gguf_config(self, gguf_path: str) -> str | None:
        """Extract super-parameters from a local GGUF file's metadata header."""
        logger = logging.getLogger(__name__)
        if GGUFReader is None:
            logger.warning("gguf package not available, cannot read GGUF metadata")
            return None
        try:
            reader = GGUFReader(gguf_path)
            config_data: dict[str, Any] = {}
            for key, field in reader.fields.items():
                try:
                    val = field.contents()
                    if isinstance(val, bytes):
                        val = val.decode("utf-8", errors="replace")
                    config_data[key] = val
                except Exception:
                    continue
            return json.dumps(config_data) if config_data else None
        except Exception:
            logger.warning("Could not read GGUF metadata from %s", gguf_path)
            return None

    def _fetch_snapshot_config(self, repo_path: str) -> str | None:
        """Extract super-parameters from a local snapshot's config.json."""
        logger = logging.getLogger(__name__)
        config_path = os.path.join(repo_path, "config.json")
        if not os.path.isfile(config_path):
            return None
        try:
            with open(config_path) as f:
                data = json.load(f)
            if isinstance(data, dict):
                return json.dumps(data)
            return None
        except Exception:
            logger.warning("Could not read config.json from %s", repo_path)
            return None

    def _fetch_model_config(self, repo_id: str, local_path: str | None = None) -> str | None:
        """Fetch model super-parameters from local files or HuggingFace API as fallback."""
        logger = logging.getLogger(__name__)

        if local_path:
            if local_path.endswith(".gguf") and os.path.isfile(local_path):
                config = self._fetch_gguf_config(local_path)
                if config:
                    logger.info("Loaded GGUF metadata from %s", local_path)
                    return config
            elif os.path.isdir(local_path):
                config = self._fetch_snapshot_config(local_path)
                if config:
                    logger.info("Loaded config.json from %s", local_path)
                    return config

        logger.info("Falling back to Hugging Face Hub API for %s...", repo_id)
        try:
            info = self.api.model_info(repo_id)
            config_data = {
                "pipeline_tag": getattr(info, "pipeline_tag", None),
                "downloads": getattr(info, "downloads", 0),
                "likes": getattr(info, "likes", 0),
                "tags": list(getattr(info, "tags", [])),
                "siblings": [s.rfilename for s in getattr(info, "siblings", [])],
            }
            return json.dumps(config_data)
        except Exception:
            logger.warning("Could not fetch model info for %s", repo_id)
            return None

    def sync_db_from_cache(self) -> dict:
        """Scan cache_dir/repos/ and ensure every model file has an AiModelRecord in the DB."""
        logger.info("Syncing database from cache directory: %s", self._repos_dir)
        added = 0
        already_present = 0
        errors = 0

        if not os.path.isdir(self._repos_dir):
            return {"added": 0, "already_present": 0, "errors": 0}

        db = db_manager.SessionLocal()
        try:
            existing_records = db.query(AiModelRecord).all()
            existing_names = {r.name for r in existing_records if r.name}

            for entry_name in os.listdir(self._repos_dir):
                folder = os.path.join(self._repos_dir, entry_name)
                logger.debug("Processing entry: %s", folder)
                if not os.path.isdir(folder):
                    continue
                if not entry_name.startswith("models--"):
                    continue
                repo_id = entry_name[len("models--"):].replace("--", "/")
                logger.info("Found repo folder: %s (repo_id: %s)", folder, repo_id)

                gguf_files = [f for f in os.listdir(folder) if f.endswith(".gguf")]
                if gguf_files:
                    logger.debug("Found GGUF files in %s: %s", folder, gguf_files)
                    api_base = os.path.join(folder, gguf_files[0])
                    model_type = "gguf"
                else:
                    api_base = folder
                    model_type = "snapshot"

                if repo_id in existing_names:
                    record = next((r for r in existing_records if r.name == repo_id), None)
                    now = datetime.utcnow()
                    if not record.all_model_files:
                        files_json, total = self._build_all_model_files_json(repo_id)
                        if files_json:
                            record.all_model_files = files_json
                            record.total_size = total if total else None
                    files_json = record.all_model_files
                    is_complete, current_total, current_files = self._is_folder_complete(folder, files_json)
                    if record:
                        record.api_base = api_base
                        record.model_type = model_type
                        record.is_local = True
                        record.download_start_at = record.download_start_at or now
                        record.created_at = record.created_at or now
                        record.is_ready = is_complete
                        record.current_total_size = current_total if current_total else None
                        record.current_model_files = current_files
                        if is_complete:
                            if not record.downloaded_at:
                                record.downloaded_at = now
                        else:
                            record.downloaded_at = None
                        if not record.config:
                            record.config = self._fetch_model_config(repo_id, local_path=api_base)
                    already_present += 1
                    continue

                logger.info("Processing new model: %s", repo_id)
                try:
                    now = datetime.utcnow()
                    all_files, all_total = self._build_all_model_files_json(repo_id)
                    current_files_json, current_total = self._build_current_model_files_json(folder)
                    record = AiModelRecord(
                        name=repo_id,
                        provider="huggingface",
                        model_type=model_type,
                        api_base=api_base,
                        is_local=True,
                        is_ready=True,
                        download_start_at=now,
                        downloaded_at=now,
                        created_at=now,
                        all_model_files=all_files,
                        current_model_files=current_files_json,
                        total_size=all_total if all_total else None,
                        current_total_size=current_total if current_total else None,
                    )
                    logger.info("Adding local model record to DB: %s", repo_id)
                    record.config = self._fetch_model_config(repo_id, local_path=api_base)
                    db.add(record)
                    existing_names.add(repo_id)
                    existing_records.append(record)
                    added += 1
                except Exception:
                    logger.warning("Failed to record %s", repo_id, exc_info=True)
                    errors += 1

            db.commit()
        except Exception:
            logger.error("sync_db_from_cache failed", exc_info=True)
            db.rollback()
            raise
        finally:
            db.close()

        logger.info("sync_db_from_cache: added=%d already_present=%d errors=%d", added, already_present, errors)
        return {"added": added, "already_present": already_present, "errors": errors}

    def _build_current_model_files_json(self, folder: str) -> tuple[str | None, int]:
        """Scan a repo folder and return (JSON dict of filename->size, total_bytes),
        or (None, 0) if the folder doesn't exist."""
        if not os.path.isdir(folder):
            return None, 0
        file_sizes: dict[str, int] = {}
        total = 0
        for root, _dirs, files in os.walk(folder):
            for fname in files:
                fpath = os.path.join(root, fname)
                rel = os.path.relpath(fpath, folder)
                try:
                    size = os.path.getsize(fpath)
                    file_sizes[rel] = size
                    total += size
                except OSError:
                    file_sizes[rel] = 0
        return (json.dumps(file_sizes) if file_sizes else None), total

    def _build_all_model_files_json(self, repo_id: str) -> tuple[str | None, int]:
        """Fetch expected file list from Hugging Face API.
        Returns (JSON dict of filename->size, total_bytes), or (None, 0) on failure."""
        try:
            meta = self.api.model_info(repo_id, files_metadata=True)
            siblings = getattr(meta, "siblings", [])
            file_sizes = {s.rfilename: (getattr(s, "size", 0) or 0) for s in siblings}
            if not file_sizes:
                return None, 0
            return json.dumps(file_sizes), sum(file_sizes.values())
        except Exception:
            return None, 0

    def _is_folder_complete(self, folder: str, all_model_files_json: str | None) -> tuple[bool, int, str | None]:
        """Verify every file in ``all_model_files`` exists on disk with matching size.
        Returns (is_complete, current_total_bytes, current_model_files_json)."""
        if not all_model_files_json:
            return False, 0, None
        try:
            expected = json.loads(all_model_files_json)
        except json.JSONDecodeError:
            return False, 0, None

        current_on_disk: dict[str, int] = {}
        current_total = 0
        current_files_json: str | None = None

        def _build_json():
            nonlocal current_files_json
            if current_files_json is None:
                current_files_json = json.dumps(current_on_disk) if current_on_disk else None

        if isinstance(expected, dict):
            for fname, expected_size in expected.items():
                fpath = os.path.join(folder, fname)
                if not os.path.isfile(fpath):
                    _build_json()
                    return False, current_total, current_files_json
                actual = os.path.getsize(fpath)
                if expected_size > 0 and actual != expected_size:
                    current_on_disk[fname] = actual
                    _build_json()
                    return False, current_total, current_files_json
                current_on_disk[fname] = actual
                current_total += actual
            _build_json()
            return True, current_total, current_files_json
        elif isinstance(expected, list):
            for fname in expected:
                fpath = os.path.join(folder, fname)
                if not os.path.isfile(fpath) or os.path.getsize(fpath) == 0:
                    _build_json()
                    return False, current_total, current_files_json
                size = os.path.getsize(fpath)
                current_on_disk[fname] = size
                current_total += size
            _build_json()
            return True, current_total, current_files_json
        _build_json()
        return False, 0, current_files_json

    def restart_unfinished_downloads(self) -> None:
        """Query all AiModelRecords with download_start_at but no downloaded_at
        and re-enqueue any unfinished downloads (e.g. after a server restart)."""
        logger.info("Checking for unfinished model downloads…")
        db = db_manager.SessionLocal()
        try:
            interrupted = db.query(AiModelRecord).filter(
                AiModelRecord.download_start_at.isnot(None),
                AiModelRecord.downloaded_at.is_(None),
            ).all()
            for rec in interrupted:
                repo_id = rec.name
                if rec.model_type == "gguf":
                    repo_folder = self._repo_folder(repo_id)
                    if os.path.isdir(repo_folder):
                        gguf_files = [f for f in os.listdir(repo_folder) if f.endswith(".gguf")]
                        if gguf_files:
                            logger.info("Re-queuing interrupted GGUF download: %s / %s", repo_id, gguf_files[0])
                            self._enqueue_download(repo_id, repo_id, filename=gguf_files[0], model_type="gguf")
                        else:
                            logger.info("No GGUF files found for interrupted download: %s, skipping", repo_id)
                    else:
                        logger.info("Repo folder not found for interrupted GGUF download: %s, skipping", repo_id)
                elif rec.model_type == "snapshot":
                    logger.info("Re-queuing interrupted snapshot download: %s", repo_id)
                    self._enqueue_download(repo_id, repo_id, model_type="snapshot")
                else:
                    logger.info("Re-queuing interrupted download (unknown type): %s", repo_id)
                    self._enqueue_download(repo_id, repo_id)
        except Exception:
            logger.error("restart_unfinished_downloads failed", exc_info=True)
        finally:
            db.close()

    def search_models(self, query: str = "gguf", limit: int = 15) -> List[Dict[str, Any]]:
        """
        Searches Hugging Face Hub for models matching the query, filtered by GGUF tags.
        """
        logger = logging.getLogger(__name__)
        try:
            models = self.api.list_models(
                search=query,
                tags="gguf",
                limit=limit,
                sort="downloads",
                direction=-1
            )
            return [{"id": m.modelId, "downloads": getattr(m, 'downloads', 0)} for m in models]
        except Exception as e:
            logger.error("Hugging Face Hub search failed: %s", e)
            raise

    def list_models(self) -> List[Dict[str, Any]]:
        """
        Lists all .gguf model files stored in structured repo folders,
        enriched with metadata from the database where available.
        """
        logger = logging.getLogger(__name__)
        results = []

        if not os.path.isdir(self._repos_dir):
            return results

        db = db_manager.SessionLocal()
        try:
            records = db.query(AiModelRecord).filter(
                AiModelRecord.api_base.isnot(None)
            ).all()
            record_map = {r.api_base: r for r in records}
        except Exception:
            logger.warning("Failed to query database for model records", exc_info=True)
            record_map = {}
        finally:
            db.close()

        try:
            for entry_name in os.listdir(self._repos_dir):
                folder = os.path.join(self._repos_dir, entry_name)
                if not os.path.isdir(folder):
                    continue
                for fname in os.listdir(folder):
                    if not fname.endswith(".gguf"):
                        continue
                    fpath = os.path.join(folder, fname)
                    record = record_map.get(fpath)
                    item: Dict[str, Any] = {"filename": fname, "size": os.path.getsize(fpath)}
                    if record:
                        item["name"] = record.name
                        item["provider"] = record.provider
                        item["model_type"] = record.model_type
                        item["is_active"] = record.is_active
                        item["created_at"] = record.created_at.isoformat() if record.created_at else None
                    results.append(item)
        except Exception as e:
            logger.error("Failed to list models in %s: %s", repos_dir, e)

        return results
    
    def is_model_downloaded(self, repo_id: str, filename: str | None = None) -> bool:
        """
        Checks if a model from a Hugging Face repository is fully downloaded.

        If *filename* is given, checks only that specific file.
        If *filename* is None, looks up the DB record's ``all_model_files``
        and verifies every file in that list exists on disk with non-zero size.
        Returns True only when all expected files are present.
        """
        repo_folder = self._repo_folder(repo_id)

        if os.path.isdir(repo_folder) is False:
            return False

        if filename is not None:
            target_path = os.path.join(repo_folder, filename)
            return os.path.isfile(target_path) and os.path.getsize(target_path) > 0

        db = db_manager.SessionLocal()
        try:
            record = db.query(AiModelRecord).filter_by(name=repo_id).first()
            if record and record.all_model_files:
                is_complete, current_total, current_files = self._is_folder_complete(repo_folder, record.all_model_files)
                changed = False
                if record.current_total_size != current_total:
                    record.current_total_size = current_total
                    changed = True
                if record.current_model_files != current_files:
                    record.current_model_files = current_files
                    changed = True
                if changed:
                    db.commit()
                return is_complete
            else:
                return False
        except Exception:
            logger.warning("Failed to check download status for %s", repo_id, exc_info=True)
        finally:
            db.close()

        return False

    def _ensure_record(self, name: str, provider: str, model_type: str | None = None,
                       all_model_files: str | None = None) -> AiModelRecord | None:
        """Upsert an AiModelRecord, returning the record (or None on failure)."""
        logger = logging.getLogger(__name__)
        db = db_manager.SessionLocal()
        try:
            existing = db.query(AiModelRecord).filter_by(name=name).first()
            if existing:
                existing.download_start_at = datetime.utcnow()
                existing.is_ready = False
                existing.downloaded_at = None
                if all_model_files is not None:
                    existing.all_model_files = all_model_files
            else:
                record = AiModelRecord(
                    name=name,
                    provider=provider,
                    model_type=model_type,
                    is_local=True,
                    download_start_at=datetime.utcnow(),
                    is_ready=False,
                    all_model_files=all_model_files,
                )
                db.add(record)
            db.commit()
            return existing or record
        except Exception:
            logger.warning("Failed to record download start in database", exc_info=True)
            db.rollback()
            return None
        finally:
            db.close()

    def _mark_done(self, name: str, api_base: str, config: str | None = None,
                    model_type: str | None = None, all_model_files: str | None = None,
                    total_size: int | None = None) -> None:
        """Update AiModelRecord after a successful download."""
        logger = logging.getLogger(__name__)
        db = db_manager.SessionLocal()
        try:
            existing = db.query(AiModelRecord).filter_by(name=name).first()
            now = datetime.utcnow()
            if existing:
                existing.api_base = api_base
                existing.is_local = True
                existing.is_ready = True
                existing.downloaded_at = now
                if config is not None:
                    existing.config = config
                if model_type is not None:
                    existing.model_type = model_type
                if all_model_files is not None:
                    existing.all_model_files = all_model_files
                    existing.current_model_files = all_model_files
                if total_size is not None:
                    existing.total_size = total_size
                    existing.current_total_size = total_size
            else:
                record = AiModelRecord(
                    name=name,
                    provider="huggingface",
                    model_type=model_type,
                    api_base=api_base,
                    config=config,
                    is_local=True,
                    is_ready=True,
                    downloaded_at=now,
                    all_model_files=all_model_files,
                    total_size=total_size,
                )
                db.add(record)
            db.commit()
        except Exception:
            logger.warning("Failed to record completed download in database", exc_info=True)
            db.rollback()
        finally:
            db.close()

    def _update_current_state(self, name: str, total: int, current_files: str | None = None) -> None:
        """Update current_total_size and current_model_files in the DB."""
        db = db_manager.SessionLocal()
        try:
            record = db.query(AiModelRecord).filter_by(name=name).first()
            if record:
                record.current_total_size = total
                if current_files is not None:
                    record.current_model_files = current_files
                db.commit()
        except Exception:
            logger.warning("Failed to update current download state for %s", name, exc_info=True)
            db.rollback()
        finally:
            db.close()

    def _download_file_with_progress(self, url: str, dest_path: str, model_name: str,
                                      total_size: int | None = None, headers: dict | None = None) -> str:
        """Download a file with progress tracking, updating the DB periodically."""
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)

        if total_size is None:
            try:
                head = requests.head(url, allow_redirects=True, headers=headers, timeout=10)
                total_size = int(head.headers.get('content-length', 0))
            except Exception:
                total_size = 0

        downloaded = 0
        last_reported = -1

        resp = requests.get(url, stream=True, headers=headers, timeout=(10, 300))
        resp.raise_for_status()

        if total_size == 0:
            total_size = int(resp.headers.get('content-length', 0))

        with open(dest_path, 'wb') as f:
            for chunk in resp.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    downloaded += len(chunk)

        return dest_path

    def download(self, repo_id: str, filename: str) -> str:
        """
        Downloads a specific model file from a repository into a structured repo folder
        (cache_dir/repos/models--repo_id/), matching the snapshot folder convention,
        and records the model in the database.
        """
        logger = logging.getLogger(__name__)
        dest_folder = self._repo_folder(repo_id)
        dest_path = os.path.join(dest_folder, filename)
        model_name = repo_id

        if self.is_model_downloaded(repo_id, filename):
            logger.info(f"Model {filename} already exists at {dest_path}. Skipping download.")
            return dest_path

        meta = self.api.model_info(repo_id, files_metadata=True)
        siblings = getattr(meta, "siblings", [])
        file_sizes = {}
        for s in siblings:
            if s.rfilename == filename:
                file_sizes[filename] = getattr(s, "size", None) or 0
                break
        if not file_sizes:
            file_sizes[filename] = 0

        file_list_json = json.dumps(file_sizes)

        self._ensure_record(model_name, "huggingface", "gguf",
                            all_model_files=file_list_json)

        try:
            logger.info("Downloading %s from %s into %s...", filename, repo_id, dest_folder)
            url = hf_hub_url(repo_id, filename)
            headers = build_hf_headers(token=self.token)
            self._download_file_with_progress(url, dest_path, model_name, headers=headers)

            logger.info("Model downloaded successfully to %s", dest_path)

            actual_size = os.path.getsize(dest_path)
            file_sizes[filename] = actual_size
            super_params = self._fetch_model_config(repo_id, local_path=dest_path)
            self._mark_done(model_name, dest_path, config=super_params, model_type="gguf",
                            all_model_files=json.dumps(file_sizes),
                            total_size=actual_size)
            # Update current_total_size after successful single-file download
            db2 = db_manager.SessionLocal()
            try:
                rec = db2.query(AiModelRecord).filter_by(name=model_name).first()
                if rec:
                    rec.current_total_size = actual_size
                    rec.current_model_files = json.dumps(file_sizes)
                    db2.commit()
            except Exception:
                db2.rollback()
            finally:
                db2.close()

            return dest_path

        except RepositoryNotFoundError:
            logger.error("Hugging Face repository not found: %s", repo_id)
            raise ValueError(f"Repository '{repo_id}' not found.")

        except RevisionNotFoundError:
            logger.error("Hugging Face revision not found for repo: %s", repo_id)
            raise ValueError(f"Revision/branch not found for repository '{repo_id}'.")

        except Exception as e:
            logger.error("Unexpected error during model download: %s", e)
            raise

    def download_snapshot(self, repo_id: str) -> str:
        """
        Downloads a full repository from Hugging Face into a structured repo folder
        (cache_dir/repos/models--repo_id/) and records the model in the database.
        Tracks overall progress across all files.
        """
        logger = logging.getLogger(__name__)
        repo_path = self._repo_folder(repo_id)

        if self.is_model_downloaded(repo_id):
            logger.info("Snapshot %s already downloaded at %s. Skipping.", repo_id, repo_path)
            return repo_path

        self._ensure_record(repo_id, "huggingface", "snapshot")

        try:
            logger.info("Downloading snapshot for %s in %s...", repo_id, repo_path)
            os.makedirs(repo_path, exist_ok=True)

            meta = self.api.model_info(repo_id, files_metadata=True)
            siblings = getattr(meta, "siblings", [])
            if not siblings:
                raise ValueError(f"No files found in repository {repo_id}")
            else:
                logger.info("From Hugging Face, there shall be %d files in repository %s totally: %s",
                            len(siblings), repo_id, [s.rfilename for s in siblings])

            file_sizes: dict[str, int] = {}
            total_bytes = 0
            for s in siblings:
                size = getattr(s, "size", None) or 0
                file_sizes[s.rfilename] = size
                total_bytes += size

            file_list_json = json.dumps(file_sizes)
            db = db_manager.SessionLocal()
            try:
                record = db.query(AiModelRecord).filter_by(name=repo_id).first()
                if record:
                    record.all_model_files = file_list_json
                    record.total_size = total_bytes if total_bytes > 0 else None
                    db.commit()
            except Exception:
                db.rollback()
            finally:
                db.close()

            if total_bytes == 0:
                total_bytes = len(siblings)
                use_count = True
            else:
                use_count = False

            downloaded_bytes = 0
            last_reported = -1
            current_on_disk: dict[str, int] = {}

            headers = build_hf_headers(token=self.token)

            for s in siblings:
                filename = s.rfilename
                dest_path = os.path.join(repo_path, filename)
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)

                if os.path.isfile(dest_path) and (
                    use_count or os.path.getsize(dest_path) == file_sizes.get(filename, 0)
                ):
                    downloaded_bytes += 1 if use_count else file_sizes[filename]
                    current_on_disk[filename] = os.path.getsize(dest_path)
                    continue

                url = hf_hub_url(repo_id, filename)
                self._download_file_with_progress(
                    url, dest_path, repo_id,
                    headers=headers,
                )

                actual = os.path.getsize(dest_path)
                current_on_disk[filename] = actual

                if use_count:
                    downloaded_bytes += 1
                    pct = int(downloaded_bytes * 100 / total_bytes)
                else:
                    downloaded_bytes += file_sizes[filename]
                    pct = int(downloaded_bytes * 100 / total_bytes)

                if pct != last_reported:
                    last_reported = pct
                    self._update_current_state(repo_id, downloaded_bytes,
                                                current_files=json.dumps(current_on_disk))

            super_params = self._fetch_model_config(repo_id, local_path=repo_path)
            self._mark_done(repo_id, repo_path, config=super_params, model_type="snapshot",
                            all_model_files=json.dumps(file_sizes),
                            total_size=total_bytes)
            return repo_path

        except Exception as e:
            logger.error("Failed to download snapshot for %s: %s", repo_id, e)
            raise

    def resolve_model(self, model_name: str) -> Dict[str, Any]:
        db = db_manager.SessionLocal()
        try:
            record = db.query(AiModelRecord).filter_by(name=model_name).first()
            if record and record.api_base and os.path.exists(record.api_base):
                t = "gguf" if record.model_type == "gguf" else "transformers"
                return {"type": t, "path": record.api_base, "is_local": record.is_local is not False}
        except Exception:
            pass
        finally:
            db.close()

        if model_name.lower().endswith(".gguf"):
            parts = model_name.rsplit("/", 2)
            if len(parts) == 3:
                model_path = self.download(f"{parts[0]}/{parts[1]}", parts[2])
            else:
                snapshot = self.download_snapshot(model_name)
                gguf_files = [f for f in os.listdir(snapshot) if f.endswith(".gguf")]
                model_path = os.path.join(snapshot, gguf_files[0]) if gguf_files else snapshot
            return {"type": "gguf", "path": model_path, "is_local": True}
        model_path = self.download_snapshot(model_name)
        return {"type": "transformers", "path": model_path, "is_local": True}

    def remove_model(self, name_or_filename: str):
        """
        Deletes a model file/folder from disk and removes its database record.
        Accepts either a repo_id ('org/modelname') or a filename ('model.gguf').
        """
        logger = logging.getLogger(__name__)
        deleted = False

        repo_folder = self._repo_folder(name_or_filename)
        if os.path.isdir(repo_folder):
            shutil.rmtree(repo_folder)
            logger.info("Deleted repo folder: %s", repo_folder)
            deleted = True
        elif os.path.isdir(self._repos_dir):
            for entry in os.listdir(self._repos_dir):
                folder = os.path.join(self._repos_dir, entry)
                if not os.path.isdir(folder):
                    continue
                fpath = os.path.join(folder, name_or_filename)
                if os.path.exists(fpath):
                    os.remove(fpath)
                    logger.info("Deleted model file: %s from %s", name_or_filename, folder)
                    deleted = True
                    if not os.listdir(folder):
                        shutil.rmtree(folder)
                        logger.info("Removed empty folder: %s", folder)
                    break

        if not deleted:
            logger.warning("Model not found on disk: %s", name_or_filename)

        db = db_manager.SessionLocal()
        try:
            records = db.query(AiModelRecord).filter(
                AiModelRecord.name == name_or_filename
            ).all()
            if not records:
                records = db.query(AiModelRecord).filter(
                    AiModelRecord.name.endswith(f"/{name_or_filename}")
                ).all()
            for record in records:
                db.delete(record)
                logger.info("Removed database record for model: %s", record.name)
            db.commit()
        except Exception:
            logger.warning("Failed to remove database record for %s", name_or_filename, exc_info=True)
            db.rollback()
        finally:
            db.close()