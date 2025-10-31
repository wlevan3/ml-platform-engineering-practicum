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


# Model Integrity Verification Tests


def test_model_integrity_verification_detects_tampering():
    """Test that hash verification detects model file tampering."""
    import shutil
    import tempfile
    from pathlib import Path

    from app.model import IrisModel, ModelIntegrityError

    with tempfile.TemporaryDirectory() as tmpdir:
        model_path = Path(tmpdir) / "iris_classifier.joblib"
        metadata_path = Path(tmpdir) / "model_metadata.json"

        # Copy original files
        shutil.copy("models/iris_classifier.joblib", model_path)
        shutil.copy("models/model_metadata.json", metadata_path)

        # Corrupt the model file
        with open(model_path, "ab") as f:
            f.write(b"CORRUPTED_DATA")

        # Attempt to load should raise ModelIntegrityError
        model = IrisModel(model_path=str(model_path), metadata_path=str(metadata_path))
        with pytest.raises(ModelIntegrityError) as exc_info:
            model.load()

        # Verify error message contains useful information
        error_msg = str(exc_info.value)
        assert "integrity verification failed" in error_msg.lower()
        assert "expected hash" in error_msg.lower()
        assert "actual hash" in error_msg.lower()


def test_model_loads_successfully_with_valid_hash():
    """Test that model loads when hash is valid."""
    from app.model import IrisModel

    model = IrisModel()
    model.load()  # Should not raise

    assert model.is_loaded()
    assert model.metadata is not None
    assert model.metadata.get("model_hash") is not None
    assert len(model.metadata["model_hash"]) == 64  # SHA-256 hex length


def test_hash_verification_happens_before_pickle_load():
    """Test that hash is verified BEFORE attempting pickle deserialization."""
    import shutil
    import tempfile
    from pathlib import Path
    from unittest.mock import patch

    from app.model import IrisModel, ModelIntegrityError

    with tempfile.TemporaryDirectory() as tmpdir:
        model_path = Path(tmpdir) / "iris_classifier.joblib"
        metadata_path = Path(tmpdir) / "model_metadata.json"

        shutil.copy("models/iris_classifier.joblib", model_path)
        shutil.copy("models/model_metadata.json", metadata_path)

        # Corrupt model
        with open(model_path, "ab") as f:
            f.write(b"TAMPERED")

        model = IrisModel(model_path=str(model_path), metadata_path=str(metadata_path))

        # Mock joblib.load to verify it's never called
        with patch("joblib.load") as mock_joblib:
            with pytest.raises(ModelIntegrityError):
                model.load()

            # joblib.load should NOT be called when hash fails
            mock_joblib.assert_not_called()


def test_model_loads_without_hash_field():
    """Test graceful handling when metadata lacks hash field."""
    import json
    import shutil
    import tempfile
    from pathlib import Path

    from app.model import IrisModel

    with tempfile.TemporaryDirectory() as tmpdir:
        model_path = Path(tmpdir) / "iris_classifier.joblib"
        metadata_path = Path(tmpdir) / "model_metadata.json"

        shutil.copy("models/iris_classifier.joblib", model_path)

        # Create metadata WITHOUT hash field (simulate old metadata)
        metadata = {
            "model_name": "iris_classifier",
            "model_version": "1.0.0",
            "classes": ["setosa", "versicolor", "virginica"],
            "features": [
                "sepal_length",
                "sepal_width",
                "petal_length",
                "petal_width",
            ],
        }
        with open(metadata_path, "w") as f:
            json.dump(metadata, f)

        # Should load successfully (hash verification is optional)
        model = IrisModel(model_path=str(model_path), metadata_path=str(metadata_path))
        model.load()  # Should not raise
        assert model.is_loaded()
