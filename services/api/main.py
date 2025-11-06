"""
FastAPI application for serving iris classification predictions.
"""

from contextlib import asynccontextmanager
from typing import Any, Dict, cast

from fastapi import FastAPI, HTTPException

from . import __version__
from .model import get_model
from .schemas import (
    LivenessResponse,
    ModelInfo,
    PredictionRequest,
    PredictionResponse,
    ReadinessResponse,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model on startup, clean up on shutdown."""
    # Startup
    model = get_model()
    try:
        model.load()
        print("✓ Model loaded successfully")
    except Exception as e:
        print(f"✗ Failed to load model: {e}")
        raise

    yield

    # Shutdown
    print("Shutting down...")


app = FastAPI(
    title="Iris Classification API",
    description="REST API for predicting iris flower species using machine learning",
    version=__version__,
    lifespan=lifespan,
)


@app.get("/health/live", response_model=LivenessResponse, tags=["Health"])
async def liveness_check():
    """
    Liveness probe endpoint for Kubernetes.

    Checks if the application process is alive and responding to requests.
    This endpoint should always return 200 OK if the process is running.
    Used by Kubernetes to determine if the container should be restarted.
    """
    return LivenessResponse(status="alive")


@app.get("/health/ready", response_model=ReadinessResponse, tags=["Health"])
async def readiness_check():
    """
    Readiness probe endpoint for Kubernetes.

    Checks if the application is ready to serve traffic (model loaded, dependencies available).
    Returns 200 OK when ready, 503 Service Unavailable when not ready.
    Used by Kubernetes to determine if traffic should be routed to this pod.
    """
    model = get_model()
    model_loaded = model.is_loaded()

    if not model_loaded:
        raise HTTPException(
            status_code=503,
            detail="Service not ready: model not loaded",
        )

    return ReadinessResponse(
        status="ready",
        model_loaded=model_loaded,
        version=__version__,
        dependencies={},  # Future: add database, feature store, etc. checks here
    )


@app.get("/model/info", response_model=ModelInfo, tags=["Model"])
async def get_model_info():
    """
    Get information about the loaded model.

    Returns model metadata including version, accuracy, features, and classes.
    """
    model = get_model()

    if not model.is_loaded():
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        info = model.get_info()
        return ModelInfo(**info)
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error retrieving model info: {str(e)}"
        )


@app.post("/predict", response_model=PredictionResponse, tags=["Predictions"])
async def predict(request: PredictionRequest):
    """
    Make a prediction for iris flower classification.

    Accepts 4 features:
    - sepal_length (cm)
    - sepal_width (cm)
    - petal_length (cm)
    - petal_width (cm)

    Returns the predicted species, confidence score, and probabilities for all classes.
    """
    model = get_model()

    if not model.is_loaded():
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        predicted_class, confidence, probabilities = model.predict(request.features)

        # Type narrowing: is_loaded() guarantees metadata is not None
        metadata = cast(Dict[str, Any], model.metadata)

        return PredictionResponse(
            prediction=predicted_class,
            confidence=confidence,
            probabilities=probabilities,
            model_version=metadata["version"],
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction error: {str(e)}")


@app.get("/", tags=["Root"])
async def root():
    """Root endpoint with API information."""
    return {
        "name": "Iris Classification API",
        "version": __version__,
        "endpoints": {
            "liveness": "/health/live",
            "readiness": "/health/ready",
            "model_info": "/model/info",
            "predict": "/predict",
            "docs": "/docs",
        },
    }
