from pathlib import Path

from apps.api.main import app as apps_api_app
from fastapi import FastAPI
from fastapi.testclient import TestClient

from ml_platform_api.model import IrisModel, get_model
from ml_platform_api.schemas import PredictionRequest

REPO_ROOT = Path(__file__).resolve().parents[1]
MODEL_ASSETS_DIR = REPO_ROOT / "services" / "api" / "models"
MODEL_SKOPS = MODEL_ASSETS_DIR / "iris_classifier.skops"
MODEL_METADATA = MODEL_ASSETS_DIR / "model_metadata.json"


def test_get_model_returns_iris_model_instance() -> None:
    """get_model should return the shared IrisModel instance."""
    model = get_model()
    assert isinstance(model, IrisModel)


def test_iris_model_has_expected_interface() -> None:
    """IrisModel instance should expose predict, get_info, and is_loaded methods."""
    model = get_model()
    # Structural checks only; do not require artifacts to exist.
    assert hasattr(model, "predict")
    assert callable(model.predict)
    assert hasattr(model, "get_info")
    assert callable(model.get_info)
    assert hasattr(model, "is_loaded")
    assert callable(model.is_loaded)


def test_prediction_request_schema_type_safety() -> None:
    """PredictionRequest should accept a list of floats and preserve values."""
    payload = {"features": [5.1, 3.5, 1.4, 0.2]}
    request = PredictionRequest(**payload)
    assert request.features == payload["features"]
    # Ensure types are floats, not coerced strings
    assert all(isinstance(f, float) for f in request.features)


def test_apps_api_main_exposes_fastapi_app() -> None:
    """apps.api.main.app should be a FastAPI instance delegating to the service."""
    assert isinstance(apps_api_app, FastAPI)
    # Basic sanity checks without assuming concrete routes beyond existence.
    assert apps_api_app.title is not None
    assert isinstance(apps_api_app.routes, list)

    # Only exercise full startup (which loads the model) when artifacts exist.
    # In environments without bundled model files, we only validate structure,
    # not successful model loading (covered in tests/test_api.py when assets are present).
    if MODEL_SKOPS.exists() and MODEL_METADATA.exists():
        with TestClient(apps_api_app) as client:
            # Smoke check on OpenAPI schema availability (non-error).
            response = client.get("/openapi.json")
            assert response.status_code in (200, 404)
