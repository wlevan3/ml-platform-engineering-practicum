#!/usr/bin/env python3
"""
Train a simple Random Forest classifier on the Iris dataset and save it.
This script creates the initial model for the prediction service.
"""

import hashlib
import joblib
import json
from pathlib import Path
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report


def calculate_file_hash(filepath: Path) -> str:
    """
    Calculate SHA-256 hash of a file.

    Args:
        filepath: Path to the file to hash

    Returns:
        Hexadecimal string representation of the SHA-256 hash
    """
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        # Read in chunks to handle large files efficiently
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def train_model() -> None:
    """Train and save an Iris classification model."""
    print("Loading Iris dataset...")
    iris = load_iris()
    X, y = iris.data, iris.target

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    print(f"Training set: {len(X_train)} samples")
    print(f"Test set: {len(X_test)} samples")

    # Train model
    print("\nTraining Random Forest classifier...")
    model = RandomForestClassifier(
        n_estimators=100, max_depth=3, random_state=42, n_jobs=-1
    )
    model.fit(X_train, y_train)

    # Evaluate
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)

    print(f"\nModel accuracy: {accuracy:.4f}")
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, target_names=iris.target_names))

    # Save model
    models_dir = Path("models")
    models_dir.mkdir(exist_ok=True)

    model_path = models_dir / "iris_classifier.joblib"
    joblib.dump(model, model_path)
    print(f"\nModel saved to: {model_path}")

    # Calculate model file hash for integrity verification
    model_hash = calculate_file_hash(model_path)
    print(f"Model SHA-256 hash: {model_hash}")

    # Save metadata
    metadata = {
        "model_type": "RandomForestClassifier",
        "version": "1.0.0",
        "accuracy": float(accuracy),
        "n_estimators": 100,
        "max_depth": 3,
        "features": iris.feature_names,
        "classes": iris.target_names.tolist(),
        "training_samples": len(X_train),
        "test_samples": len(X_test),
        "model_file": "iris_classifier.joblib",
        "model_hash": model_hash,
        "hash_algorithm": "SHA-256",
    }

    metadata_path = models_dir / "model_metadata.json"
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)
    print(f"Metadata saved to: {metadata_path}")


if __name__ == "__main__":
    train_model()
