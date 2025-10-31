"""
FastAPI application for serving iris classification predictions.
"""

from contextlib import asynccontextmanager
from typing import Any, Dict, cast

from fastapi import FastAPI, HTTPException

from app import __version__
from app.model import get_model
from app.schemas import PredictionRequest, PredictionResponse, HealthResponse, ModelInfo


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


@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """
    Health check endpoint.

    Returns the service health status and whether the model is loaded.
    """
    model = get_model()
    return HealthResponse(
        status="healthy", model_loaded=model.is_loaded(), version=__version__
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
            "health": "/health",
            "model_info": "/model/info",
            "predict": "/predict",
            "docs": "/docs",
        },
    }
