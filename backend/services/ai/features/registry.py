import logging
import threading
from typing import Any, Optional
from backend.db.database import db_manager, FeatureModelRecord


class FeatureRegistry:
    def __init__(self, status=None):
        self.logger = logging.getLogger(__name__)
        self._features: dict[str, Any] = {}
        self._status = status

    def register(self, name: str, feature: Any) -> None:
        self.logger.info("Registering feature: %s", name)
        if name in self._features:
            self.logger.warning("Overwriting existing feature: %s", name)
        self._features[name] = feature
        self.logger.info("Feature registered: %s", name)

    def unregister(self, name: str) -> None:
        self.logger.info("Unregistering feature: %s", name)
        self._features.pop(name, None)
        self.logger.info("Feature unregistered: %s", name)

    def get(self, name: str) -> Optional[Any]:
        return self._features.get(name)

    def list_features(self) -> dict[str, Any]:
        return dict(self._features)

    def list_with_models(self) -> list[dict[str, Any]]:
        results = []
        for name, feature in self._features.items():
            model_name = getattr(feature, "model_name", None)
            results.append({
                "name": name,
                "model_name": model_name,
                "functionality": getattr(feature, "functionality", name),
                "feature_title": getattr(feature, "feature_title", None),
                "feature_description": getattr(feature, "feature_description", None),
            })
        return results

    def _save_feature_record(self, name: str, model_name: str, feature: Any) -> None:
        db = db_manager.SessionLocal()
        try:
            record = db.query(FeatureModelRecord).filter_by(functionality=name).first()
            if record:
                record.model_name = model_name
                if getattr(feature, "feature_title", None):
                    record.feature_title = feature.feature_title
                if getattr(feature, "feature_description", None):
                    record.feature_description = feature.feature_description
            else:
                db.add(FeatureModelRecord(
                    functionality=name,
                    model_name=model_name,
                    feature_title=getattr(feature, "feature_title", None),
                    feature_description=getattr(feature, "feature_description", None),
                ))
            db.commit()
        finally:
            db.close()

    def set_feature_model(self, name: str, model_name: str, model_service=None) -> None:
        self.logger.info("Setting model for feature '%s': %s", name, model_name)
        feature = self._features.get(name)
        if not feature:
            raise ValueError(f"Feature '{name}' is not registered.")

        if not hasattr(feature, "set_model"):
            raise ValueError(f"Feature '{name}' does not support set_model.")

        feature.set_model(model_name, model_service=model_service)
        self._save_feature_record(name, model_name, feature)

    def set_feature_model_async(self, name: str, model_name: str,
                                model_service=None) -> None:
        self.logger.info("Starting async model load for '%s': %s", name, model_name)
        feature = self._features.get(name)
        if not feature:
            raise ValueError(f"Feature '{name}' is not registered.")
        if not hasattr(feature, "set_model"):
            raise ValueError(f"Feature '{name}' does not support set_model.")

        if self._status:
            self._status.update_feature_state(name, model_name, "loading")

        def _load():
            try:
                feature.set_model(model_name, model_service=model_service)
                self._save_feature_record(name, model_name, feature)
                if self._status:
                    self._status.update_feature_state(name, model_name, "ready")
                    self._status.sync_features_list(self)
                self.logger.info("Model for '%s' loaded successfully: %s", name, model_name)
            except Exception as e:
                self.logger.error("Failed to load model for '%s': %s", name, e)
                if self._status:
                    self._status.update_feature_state(name, model_name, "error", str(e))

        threading.Thread(target=_load, daemon=True).start()
