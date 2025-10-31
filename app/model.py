"""
ML model loading and prediction logic.
"""

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, cast

import joblib
import numpy as np
from sklearn.base import ClassifierMixin


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
        self.model: Optional[ClassifierMixin] = None
        self.metadata: Optional[Dict[str, Any]] = None
        self.classes: Optional[List[str]] = None

    def load(self) -> None:
        """Load the model and metadata from disk."""
        if not self.model_path.exists():
            raise FileNotFoundError(f"Model file not found: {self.model_path}")

        if not self.metadata_path.exists():
            raise FileNotFoundError(f"Metadata file not found: {self.metadata_path}")

        # Load model
        loaded_model = joblib.load(self.model_path)
        if not isinstance(loaded_model, ClassifierMixin):
            raise TypeError("Loaded model is not a scikit-learn classifier.")
        self.model = loaded_model

        # Load metadata
        with open(self.metadata_path, "r") as f:
            metadata_raw = json.load(f)

        if not isinstance(metadata_raw, dict):
            raise ValueError("Model metadata must be a JSON object.")

        metadata = cast(Dict[str, Any], metadata_raw)

        classes = metadata.get("classes")
        if not isinstance(classes, list) or not all(isinstance(label, str) for label in classes):
            raise ValueError("Model metadata must define 'classes' as a list of strings.")

        version = metadata.get("version")
        if not isinstance(version, str):
            raise ValueError("Model metadata must define 'version' as a string.")

        self.metadata = metadata
        self.classes = classes

    def predict(self, features: List[float]) -> Tuple[str, float, Dict[str, float]]:
        """
        Make a prediction for the given features.

        Args:
            features: List of 4 float values representing iris measurements

        Returns:
            Tuple of (predicted_class, confidence, probabilities_dict)
        """
        model = self.model
        classes = self.classes

        if model is None or classes is None:
            raise RuntimeError("Model not loaded. Call load() first.")

        if len(features) != 4:
            raise ValueError(f"Expected 4 features, got {len(features)}")

        # Convert to numpy array and reshape for single prediction
        X = np.array(features).reshape(1, -1)

        # Get prediction and probabilities
        prediction = model.predict(X)[0]
        probabilities = model.predict_proba(X)[0]

        # Get predicted class name
        predicted_class = classes[prediction]

        # Get confidence (probability of predicted class)
        confidence = float(probabilities[prediction])

        # Create probabilities dictionary
        prob_dict = {
            class_name: float(prob)
            for class_name, prob in zip(classes, probabilities)
        }

        return predicted_class, confidence, prob_dict

    def get_info(self) -> Dict[str, Any]:
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
        return (
            self.model is not None
            and self.metadata is not None
            and self.classes is not None
        )


# Global model instance
_model = IrisModel()


def get_model() -> IrisModel:
    """
    Get the global model instance.

    Returns:
        The global IrisModel instance
    """
    return _model
