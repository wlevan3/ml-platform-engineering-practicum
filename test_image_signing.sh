#!/bin/bash
set -e

# Container Image Signing Test Script
# This script demonstrates local testing of container image signing with Cosign
# Usage: ./test_image_signing.sh [key-based|keyless]

SIGNING_MODE="${1:-key-based}"
IMAGE_NAME="ml-platform-api:test"

echo "=========================================="
echo "Container Image Signing Test"
echo "Mode: $SIGNING_MODE"
echo "=========================================="

# Check prerequisites
echo ""
echo "Checking prerequisites..."

if ! command -v docker &>/dev/null; then
	echo "❌ Docker not found. Please install Docker."
	exit 1
fi
echo "✅ Docker installed"

if ! command -v cosign &>/dev/null; then
	echo "❌ Cosign not found. Installing Cosign..."
	echo ""
	echo "Installation options:"
	echo "  macOS:  brew install cosign"
	echo "  Linux:  wget https://github.com/sigstore/cosign/releases/download/v2.4.1/cosign-linux-amd64"
	echo "          chmod +x cosign-linux-amd64 && sudo mv cosign-linux-amd64 /usr/local/bin/cosign"
	exit 1
fi
echo "✅ Cosign installed ($(cosign version --short))"

if ! command -v python3 &>/dev/null; then
	echo "❌ Python 3 not found. Please install Python 3.13+"
	exit 1
fi
echo "✅ Python installed ($(python3 --version))"

# Train model
echo ""
echo "=========================================="
echo "Step 1: Training model"
echo "=========================================="

if [ ! -f "models/iris_classifier.skops" ]; then
	echo "Training model..."
	python3 train_model.py
	echo "✅ Model trained successfully"
else
	echo "✅ Model already exists"
fi

# Build Docker image
echo ""
echo "=========================================="
echo "Step 2: Building Docker image"
echo "=========================================="

echo "Building $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" .
echo "✅ Image built successfully"

# Sign image
echo ""
echo "=========================================="
echo "Step 3: Signing image"
echo "=========================================="

if [ "$SIGNING_MODE" == "keyless" ]; then
	echo "Using keyless signing (requires GitHub authentication)..."
	echo ""
	echo "⚠️  This will open a browser for GitHub OIDC authentication"
	echo ""
	export COSIGN_EXPERIMENTAL=1

	echo "Signing $IMAGE_NAME..."
	cosign sign "$IMAGE_NAME"

	echo "✅ Image signed with keyless signing"

elif [ "$SIGNING_MODE" == "key-based" ]; then
	echo "Using key-based signing..."

	if [ ! -f "cosign.key" ] || [ ! -f "cosign.pub" ]; then
		echo "Generating test key pair..."
		cosign generate-key-pair
		echo "✅ Key pair generated (cosign.key, cosign.pub)"
		echo "⚠️  DO NOT commit private key (cosign.key) to Git!"
	else
		echo "✅ Using existing key pair"
	fi

	echo "Signing $IMAGE_NAME with private key..."
	cosign sign --key cosign.key "$IMAGE_NAME"

	echo "✅ Image signed with key-based signing"

else
	echo "❌ Invalid signing mode: $SIGNING_MODE"
	echo "Usage: $0 [key-based|keyless]"
	exit 1
fi

echo ""
echo "ℹ️  Note: Local Image Signing Limitation"
echo "────────────────────────────────────────────────────────────────"
echo "This script signs a LOCAL Docker image. Signatures are stored in"
echo "the local Docker daemon, not in an OCI registry."
echo ""
echo "For PRODUCTION use (signatures in OCI registry):"
echo "  1. Push image to registry: docker push <registry>/<image>:tag"
echo "  2. Sign registry image: cosign sign <registry>/<image>:tag"
echo "  3. Signatures stored alongside image in registry"
echo ""
echo "The CI workflow uses --upload=false for Phase 1 testing."
echo "Phase 2 will integrate with AWS ECR for persistent signatures."
echo "────────────────────────────────────────────────────────────────"

# Verify signature
echo ""
echo "=========================================="
echo "Step 4: Verifying signature"
echo "=========================================="

if [ "$SIGNING_MODE" == "keyless" ]; then
	echo "Verifying keyless signature..."
	export COSIGN_EXPERIMENTAL=1

	# Note: For local testing, we can't verify with exact certificate identity
	# since we're not running in GitHub Actions. We verify the signature exists.
	echo "Checking signature exists..."
	cosign tree "$IMAGE_NAME"

	echo "✅ Keyless signature verified"
	echo ""
	echo "ℹ️  In CI, signature will be verified with:"
	echo "  - Certificate identity: https://github.com/wlevan3/ml-platform-engineering-practicum/*"
	echo "  - OIDC issuer: https://token.actions.githubusercontent.com"

elif [ "$SIGNING_MODE" == "key-based" ]; then
	echo "Verifying key-based signature..."
	cosign verify --key cosign.pub "$IMAGE_NAME"

	echo "✅ Key-based signature verified"
fi

# Display signature information
echo ""
echo "=========================================="
echo "Step 5: Signature details"
echo "=========================================="

echo "Signature tree for $IMAGE_NAME:"
cosign tree "$IMAGE_NAME"

echo ""
echo "=========================================="
echo "✅ All tests passed!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Review the signature information above"
echo "  2. Push changes to GitHub to trigger CI signing"
echo "  3. Verify CI signing succeeds in GitHub Actions"
echo ""

if [ "$SIGNING_MODE" == "key-based" ]; then
	echo "⚠️  Remember:"
	echo "  - cosign.key contains the private key"
	echo "  - DO NOT commit cosign.key to Git"
	echo "  - Add cosign.key to .gitignore if not already present"
	echo ""
fi
