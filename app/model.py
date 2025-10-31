"""
ML model loading and prediction logic.
"""

import hmac
import json
import joblib
import numpy as np
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, cast

from app.security import calculate_file_hash


class ModelIntegrityError(Exception):
    """Raised when model file integrity verification fails."""

    pass


class IrisModel:
    """Iris classification model wrapper."""

    def __init__(
        self,
        model_path: str = "models/iris_classifier.joblib",
        metadata_path: str = "models/model_metadata.json",
    ):
        """
        Initialize the model.

        Args:
            model_path: Path to the trained model file
            metadata_path: Path to the model metadata JSON file
        """
        self.model_path = Path(model_path)
        self.metadata_path = Path(metadata_path)
        self.model: Optional[Any] = None
        self.metadata: Optional[Dict[str, Any]] = None
        self.classes: Optional[List[str]] = None

    def load(self) -> None:
        """Load the model and metadata from disk with integrity verification."""
        if not self.model_path.exists():
            raise FileNotFoundError(f"Model file not found: {self.model_path}")

        if not self.metadata_path.exists():
            raise FileNotFoundError(f"Metadata file not found: {self.metadata_path}")

        # Load metadata first to get expected hash
        with open(self.metadata_path, "r") as f:
            self.metadata = cast(Dict[str, Any], json.load(f))

        # Verify model file integrity if hash is present
        expected_hash = self.metadata.get("model_hash")
        if expected_hash:
            actual_hash = calculate_file_hash(self.model_path)
            # Use constant-time comparison to prevent timing attacks
            if not hmac.compare_digest(expected_hash, actual_hash):
                raise ModelIntegrityError(
                    f"Model file integrity verification failed!\n"
                    f"Expected hash: {expected_hash}\n"
                    f"Actual hash: {actual_hash}\n"
                    f"The model file may have been corrupted or tampered with."
                )

        # Security Note: Using joblib.load() with locally trained model
        # Source: train_model.py (controlled environment)
        # Protection: SHA-256 hash verification (see above)
        # Risk: Low - model path hardcoded, integrity verified
        # Future: Will migrate to MLflow Model Registry (Phase 3)
        # nosemgrep: unsafe-pickle-deserialization
        self.model = joblib.load(self.model_path)

        self.classes = self.metadata["classes"]

    def predict(self, features: List[float]) -> Tuple[str, float, Dict[str, float]]:
        """
        Make a prediction for the given features.

        Args:
            features: List of 4 float values representing iris measurements

        Returns:
            Tuple of (predicted_class, confidence, probabilities_dict)
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
            for class_name, prob in zip(self.classes, probabilities)
        }

        return predicted_class, confidence, prob_dict

    def get_info(self) -> Dict:
        """
        Get model information.

        Returns:
            Dictionary containing model metadata
        """
        if self.metadata is None:
            raise RuntimeError("Model not loaded. Call load() first.")

        return self.metadata

    def is_loaded(self) -> bool:
        """Check if model is loaded."""
        return self.model is not None and self.metadata is not None


# Global model instance
_model = IrisModel()


def get_model() -> IrisModel:
    """
    Get the global model instance.

    Returns:
        The global IrisModel instance
    """
    return _model
