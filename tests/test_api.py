"""
Unit tests for FastAPI endpoints.
"""

import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.model import get_model


@pytest.fixture(scope="module")
def client():
    """Create a test client with lifespan context."""
    # Pre-load the model for tests
    model = get_model()
    model.load()

    with TestClient(app) as test_client:
        yield test_client


def test_root_endpoint(client):
    """Test the root endpoint returns API information."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "name" in data
    assert "version" in data
    assert "endpoints" in data
    assert data["name"] == "Iris Classification API"


def test_health_endpoint(client):
    """Test the health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["model_loaded"] is True
    assert "version" in data


def test_model_info_endpoint(client):
    """Test the model info endpoint."""
    response = client.get("/model/info")
    assert response.status_code == 200
    data = response.json()
    assert "model_type" in data
    assert "version" in data
    assert "accuracy" in data
    assert "features" in data
    assert "classes" in data
    assert data["model_type"] == "RandomForestClassifier"
    assert len(data["features"]) == 4
    assert len(data["classes"]) == 3
    assert set(data["classes"]) == {"setosa", "versicolor", "virginica"}


def test_predict_setosa(client):
    """Test prediction for iris setosa."""
    # Typical setosa measurements: short petals
    response = client.post("/predict", json={"features": [5.1, 3.5, 1.4, 0.2]})
    assert response.status_code == 200
    data = response.json()
    assert data["prediction"] == "setosa"
    assert data["confidence"] > 0.8
    assert "probabilities" in data
    assert "model_version" in data
    assert set(data["probabilities"].keys()) == {"setosa", "versicolor", "virginica"}


def test_predict_versicolor(client):
    """Test prediction for iris versicolor."""
    # Typical versicolor measurements: medium petals
    response = client.post("/predict", json={"features": [5.9, 3.0, 4.2, 1.5]})
    assert response.status_code == 200
    data = response.json()
    assert data["prediction"] == "versicolor"
    assert 0.0 <= data["confidence"] <= 1.0
    assert "probabilities" in data


def test_predict_virginica(client):
    """Test prediction for iris virginica."""
    # Typical virginica measurements: long petals
    response = client.post("/predict", json={"features": [6.5, 3.0, 5.5, 2.0]})
    assert response.status_code == 200
    data = response.json()
    assert data["prediction"] == "virginica"
    assert 0.0 <= data["confidence"] <= 1.0
    assert "probabilities" in data


def test_predict_invalid_features_count(client):
    """Test prediction with wrong number of features."""
    # Only 3 features instead of 4
    response = client.post("/predict", json={"features": [5.1, 3.5, 1.4]})
    assert response.status_code == 422  # Validation error


def test_predict_invalid_features_type(client):
    """Test prediction with invalid feature types."""
    response = client.post(
        "/predict", json={"features": ["not", "a", "number", "list"]}
    )
    assert response.status_code == 422  # Validation error


def test_predict_missing_features(client):
    """Test prediction with missing features field."""
    response = client.post("/predict", json={})
    assert response.status_code == 422  # Validation error


def test_openapi_docs(client):
    """Test that OpenAPI documentation is available."""
    response = client.get("/openapi.json")
    assert response.status_code == 200
    data = response.json()
    assert "openapi" in data
    assert "info" in data
    assert "paths" in data
    assert "/predict" in data["paths"]
    assert "/health" in data["paths"]
    assert "/model/info" in data["paths"]
