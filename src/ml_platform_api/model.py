"""Canonical ML model loading and prediction logic for the ML platform API.

This module hosts the IrisModel and helpers as the authoritative implementation.
Compatibility shims (e.g. services.api.model) re-export from here per STREAMLINING_PLAN.
"""

import hmac
import json
from pathlib import Path
from typing import Any, cast

import numpy as np
import skops.io as sio

from ml_platform_api.security import calculate_file_hash


class ModelIntegrityError(Exception):
    """Raised when model file integrity verification fails."""


class IrisModel:
    """Iris classification model wrapper."""

    def __init__(
        self,
        model_path: str | None = None,
        metadata_path: str | None = None,
    ) -> None:
        """
        Initialize the model.

        Args:
            model_path: Path to the trained model file.
            metadata_path: Path to the model metadata JSON file.
        """
        # Preserve original behavior:
        # models are stored under services/api/models relative to this repo.
        repo_root = Path(__file__).resolve().parents[2]
        models_dir = repo_root / "services" / "api" / "models"

        self.model_path: Path = (
            Path(model_path) if model_path is not None else models_dir / "iris_classifier.skops"
        )
        self.metadata_path: Path = (
            Path(metadata_path) if metadata_path is not None else models_dir / "model_metadata.json"
        )
        # Underlying model object from skops/sklearn is not precisely typed here.
        self.model: Any | None = None
        self.metadata: dict[str, Any] | None = None
        self.classes: list[str] | None = None

    def load(self) -> None:
        """Load the model and metadata from disk with integrity verification."""
        if not self.model_path.exists():
            raise FileNotFoundError(f"Model file not found: {self.model_path}")

        if not self.metadata_path.exists():
            raise FileNotFoundError(f"Metadata file not found: {self.metadata_path}")

        # Load metadata first to get expected hash
        with open(self.metadata_path) as f:
            loaded_metadata = json.load(f)
        # Ensure metadata is a dictionary for typing purposes
        if not isinstance(loaded_metadata, dict):
            raise ModelIntegrityError("Invalid metadata format: expected JSON object")
        self.metadata = cast(dict[str, Any], loaded_metadata)

        # Verify model file integrity if hash is present
        expected_hash = self.metadata.get("model_hash")
        if expected_hash:
            # Use hash algorithm from metadata, default to sha256
            # Normalize algorithm name: "SHA-256" -> "sha256"
            hash_algorithm = self.metadata.get("hash_algorithm", "sha256")
            hash_algorithm = hash_algorithm.lower().replace("-", "")
            actual_hash = calculate_file_hash(
                self.model_path,
                algorithm=hash_algorithm,
            )
            # Use constant-time comparison to prevent timing attacks
            if not hmac.compare_digest(expected_hash, actual_hash):
                raise ModelIntegrityError(
                    "Model file integrity verification failed!\n"
                    f"Expected hash: {expected_hash}\n"
                    f"Actual hash: {actual_hash}\n"
                    "The model file may have been corrupted or tampered with."
                )

        # Security: Using skops.io.load() - pickle-free deserialization
        # Hash verification (above): Ensures file integrity (detects tampering)
        # skops.io: Provides execution safety (prevents code execution)
        untrusted_types = sio.get_untrusted_types(file=self.model_path)
        if untrusted_types:
            # For locally trained models, untrusted_types should be empty
            # If not empty, model contains types outside sklearn/numpy defaults
            raise ModelIntegrityError(
                f"Model contains untrusted types: {untrusted_types}\n"
                "This model may not have been trained in a controlled "
                "environment. Review these types before loading or "
                "retrain the model."
            )

        # nosemgrep: skops-untrusted-load (validated above: untrusted_types checked)
        self.model = sio.load(self.model_path, trusted=untrusted_types)
        if self.metadata is None:
            raise ModelIntegrityError("Metadata must be loaded before model.")
        classes_value = self.metadata.get("classes")
        if not isinstance(classes_value, list):
            raise ModelIntegrityError("Metadata 'classes' must be a list.")
        # mypy: assume classes list contains strings;
        # runtime validation is minimal to avoid behavior change
        self.classes = [str(c) for c in classes_value]

    def predict(self, features: list[float]) -> tuple[str, float, dict[str, float]]:
        """
        Make a prediction for the given features.

        Args:
            features: List of 4 float values representing iris measurements.

        Returns:
            Tuple of (predicted_class, confidence, probabilities_dict).
        """
        if self.model is None:
            raise RuntimeError("Model not loaded. Call load() first.")

        if self.classes is None:
            raise RuntimeError("Model classes not loaded. Call load() first.")

        if len(features) != 4:
            raise ValueError(f"Expected 4 features, got {len(features)}")

        # Convert to numpy array and reshape for single prediction
        X = np.array(features).reshape(1, -1)

        # Get prediction and probabilities
        prediction = self.model.predict(X)[0]
        probabilities = self.model.predict_proba(X)[0]

        # Get predicted class name
        predicted_class = self.classes[prediction]

        # Get confidence (probability of predicted class)
        confidence = float(probabilities[prediction])

        # Create probabilities dictionary
        prob_dict = {
            class_name: float(prob)
            for class_name, prob in zip(self.classes, probabilities, strict=True)
        }

        return predicted_class, confidence, prob_dict

    def get_info(self) -> dict[str, Any]:
        """Get model information from metadata."""
        if self.metadata is None:
            raise RuntimeError("Model not loaded. Call load() first.")
        return self.metadata

    def is_loaded(self) -> bool:
        """Check if model is loaded."""
        return self.model is not None and self.metadata is not None


# Global model instance (preserving prior behavior)
_model: IrisModel = IrisModel()


def get_model() -> IrisModel:
    """
    Get the global model instance.

    Returns:
        The global IrisModel instance.
    """
    return _model
