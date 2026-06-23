import time
import threading
from dataclasses import dataclass, field
from typing import Any


@dataclass
class AIStatus:
    status: str = "loading"
    features: list[dict[str, Any]] = field(default_factory=list)
    models_available: int = 0
    error: str | None = None
    started_at: float = field(default_factory=time.time)
    feature_states: dict[str, dict[str, Any]] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    @property
    def elapsed(self) -> float:
        return time.time() - self.started_at

    def update_feature_state(self, name: str, model_name: str,
                             status: str, error: str | None = None) -> None:
        with self._lock:
            self.feature_states[name] = {
                "name": name,
                "model_name": model_name,
                "status": status,
                "error": error,
            }

    def sync_features_list(self, registry) -> None:
        with self._lock:
            self.features = registry.list_with_models()
            for f in self.features:
                fn = f["name"]
                fs = self.feature_states.get(fn)
                if fs:
                    f["status"] = fs["status"]
                    if fs.get("error"):
                        f["error"] = fs["error"]
                else:
                    f["status"] = "unknown"
