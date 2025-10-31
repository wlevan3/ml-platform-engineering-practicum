"""
ML model loading and prediction logic.
"""

import json
import joblib
import numpy as np
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


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
        """Load the model and metadata from disk."""
        if not self.model_path.exists():
            raise FileNotFoundError(f"Model file not found: {self.model_path}")

        if not self.metadata_path.exists():
            raise FileNotFoundError(f"Metadata file not found: {self.metadata_path}")

        # Load model
        self.model = joblib.load(self.model_path)

        # Load metadata
        with open(self.metadata_path, "r") as f:
            self.metadata = json.load(f)

        if self.metadata is None:
            raise RuntimeError("Failed to load metadata from JSON")

        # Type narrowing: mypy now knows self.metadata is not None
        assert self.metadata is not None, "Metadata should be loaded"
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
