"""Pydantic models for request/response validation.

Canonical location for API schemas; services.api.schemas is a shim that re-exports from this module.
"""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class PredictionRequest(BaseModel):
    """Request model for iris flower predictions."""

    features: list[float] = Field(
        ...,
        min_length=4,
        max_length=4,
        description=(
            "Iris flower measurements: [sepal_length, sepal_width, petal_length, petal_width] in cm"
        ),
        examples=[[5.1, 3.5, 1.4, 0.2]],
    )

    model_config = ConfigDict(json_schema_extra={"examples": [{"features": [5.1, 3.5, 1.4, 0.2]}]})


class PredictionResponse(BaseModel):
    """Response model for iris flower predictions."""

    prediction: str = Field(..., description="Predicted iris species")
    confidence: float = Field(
        ...,
        ge=0.0,
        le=1.0,
        description="Prediction confidence score",
    )
    probabilities: dict[str, float] = Field(
        ...,
        description="Probability for each class",
    )
    model_version: str = Field(..., description="Version of the model used")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "prediction": "setosa",
                    "confidence": 0.99,
                    "probabilities": {
                        "setosa": 0.99,
                        "versicolor": 0.01,
                        "virginica": 0.00,
                    },
                    "model_version": "1.0.0",
                }
            ]
        }
    )


class LivenessResponse(BaseModel):
    """Response model for liveness probe endpoint.

    Liveness probe checks if the application process is alive and responding.
    This should always return 200 OK if the process can handle requests.
    """

    status: Literal["alive"] = Field(
        default="alive",
        description="Liveness status - always 'alive' if responding",
    )

    model_config = ConfigDict(json_schema_extra={"examples": [{"status": "alive"}]})


class ReadinessResponse(BaseModel):
    """Response model for readiness probe endpoint.

    Readiness probe checks if the application is ready to serve traffic.
    Returns 200 OK when model is loaded, 503 when not ready.
    """

    status: Literal["ready"] = Field(
        default="ready",
        description=("Readiness status - always 'ready' when responding with 200"),
    )
    model_loaded: bool = Field(
        ...,
        description="Whether the ML model is loaded",
    )
    version: str = Field(
        ...,
        description="API version",
    )
    dependencies: dict[str, str] = Field(
        default_factory=dict,
        description=(
            "Status of dependencies (empty for now, future-proof for "
            "databases, feature stores, etc.)"
        ),
    )

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "status": "ready",
                    "model_loaded": True,
                    "version": "1.0.0",
                    "dependencies": {},
                }
            ]
        }
    )


class ModelInfo(BaseModel):
    """Response model for model information endpoint."""

    model_type: str = Field(..., description="Type of ML model")
    version: str = Field(..., description="Model version")
    accuracy: float = Field(..., description="Model accuracy on test set")
    features: list[str] = Field(..., description="Feature names")
    classes: list[str] = Field(..., description="Output class names")
    training_samples: int = Field(
        ...,
        description="Number of training samples",
    )
    test_samples: int = Field(
        ...,
        description="Number of test samples",
    )
