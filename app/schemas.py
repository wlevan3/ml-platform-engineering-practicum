"""
Pydantic models for request/response validation.
"""

from typing import List
from pydantic import BaseModel, Field, ConfigDict


class PredictionRequest(BaseModel):
    """Request model for iris flower predictions."""

    features: List[float] = Field(
        ...,
        min_length=4,
        max_length=4,
        description="Iris flower measurements: [sepal_length, sepal_width, petal_length, petal_width] in cm",
        examples=[[5.1, 3.5, 1.4, 0.2]]
    )

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "features": [5.1, 3.5, 1.4, 0.2]
                }
            ]
        }
    )


class PredictionResponse(BaseModel):
    """Response model for iris flower predictions."""

    prediction: str = Field(
        ...,
        description="Predicted iris species"
    )
    confidence: float = Field(
        ...,
        ge=0.0,
        le=1.0,
        description="Prediction confidence score"
    )
    probabilities: dict[str, float] = Field(
        ...,
        description="Probability for each class"
    )
    model_version: str = Field(
        ...,
        description="Version of the model used"
    )

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "prediction": "setosa",
                    "confidence": 0.99,
                    "probabilities": {
                        "setosa": 0.99,
                        "versicolor": 0.01,
                        "virginica": 0.00
                    },
                    "model_version": "1.0.0"
                }
            ]
        }
    )


class HealthResponse(BaseModel):
    """Response model for health check endpoint."""

    status: str = Field(
        ...,
        description="Service health status"
    )
    model_loaded: bool = Field(
        ...,
        description="Whether the ML model is loaded"
    )
    version: str = Field(
        ...,
        description="API version"
    )


class ModelInfo(BaseModel):
    """Response model for model information endpoint."""

    model_type: str = Field(
        ...,
        description="Type of ML model"
    )
    version: str = Field(
        ...,
        description="Model version"
    )
    accuracy: float = Field(
        ...,
        description="Model accuracy on test set"
    )
    features: List[str] = Field(
        ...,
        description="Feature names"
    )
    classes: List[str] = Field(
        ...,
        description="Output class names"
    )
    training_samples: int = Field(
        ...,
        description="Number of training samples"
    )
    test_samples: int = Field(
        ...,
        description="Number of test samples"
    )
