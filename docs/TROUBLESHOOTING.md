# Troubleshooting Guide

Common issues and solutions for ML Platform Engineering Practicum.

## Table of Contents

- [Environment Setup](#environment-setup)
- [Pre-Commit Hooks](#pre-commit-hooks)
- [Testing](#testing)
- [API Server](#api-server)
- [Docker](#docker)
- [Kubernetes](#kubernetes)
- [Git & GitHub](#git--github)
- [SonarCloud](#sonarcloud)
- [Security Scanning](#security-scanning)
- [Model Loading](#model-loading)
- [CI/CD Issues](#cicd-issues)
- [Getting Help](#getting-help)

## Environment Setup

### Python Version Issues

**Problem**: `ModuleNotFoundError`, import errors, or syntax errors

```bash
ModuleNotFoundError: No module named 'app'
```

**Solution**: Verify Python 3.13+ is active

```bash
# Check Python version
python --version  # Should show 3.13.x

# If wrong version, activate correct environment
source .venv/bin/activate  # macOS/Linux
.venv\Scripts\activate     # Windows

# Verify again
python --version
```

---

### Virtual Environment Not Found

**Problem**: `bash: .venv/bin/activate: No such file or directory`

**Solution**: Create virtual environment first

```bash
# Create venv with Python 3.13
python3.13 -m venv .venv

# Activate
source .venv/bin/activate  # macOS/Linux
.venv\Scripts\activate     # Windows

# Install dependencies
pip install -r requirements.txt
```

**Alternative (using uv)**:

```bash
# Install uv (recommended)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create and sync environment
uv sync
```

---

### Dependency Installation Fails

**Problem**: `pip install` errors, version conflicts

**Solution 1 - Clean reinstall**:

```bash
# Remove existing venv
rm -rf .venv

# Create fresh venv
python3.13 -m venv .venv
source .venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install dependencies
pip install -r requirements.txt
```

**Solution 2 - Use uv (recommended)**:

```bash
# uv handles dependency resolution better
uv sync
```

---

## Pre-Commit Hooks

### Pre-Commit Not Installed

**Problem**: Commit succeeds without running checks (secrets, linting)

**Solution**: Install pre-commit hooks

```bash
# Install pre-commit package
pip install pre-commit

# Install git hooks
pre-commit install

# Verify installation
pre-commit run --all-files
```

---

### Pre-Commit Hook Fails

**Problem**: Commit blocked by pre-commit checks

```bash
detect-secrets...........................................................Failed
```

**Common Failures**:

**1. Secrets Detected**:

```bash
# Review what was detected
detect-secrets scan

# If false positive, update baseline
detect-secrets scan --baseline .secrets.baseline

# Re-commit
git add .secrets.baseline
git commit -m "Update secrets baseline"
```

**2. Code Formatting (black)**:

```bash
# Black will auto-fix most issues
black .

# Re-stage and commit
git add .
git commit -m "Your message"
```

**3. Linting Errors (ruff)**:

```bash
# Check what failed
ruff check .

# Auto-fix where possible
ruff check --fix .

# Re-stage and commit
git add .
git commit -m "Your message"
```

**4. Type Checking (mypy)**:

```bash
# Review type errors
mypy app/

# Fix type hints in flagged files
# Then re-commit
```

---

### Skip Pre-Commit (Emergency Only)

**WARNING**: Only use if absolutely necessary (e.g., fixing broken commit)

```bash
# Skip hooks (NOT recommended for security hooks)
git commit -m "Your message" --no-verify
```

**When to use**: Never for secrets, very rarely for formatting

---

## Testing

### Tests Fail

**Problem**: `pytest` exits with failures

**Solution 1 - Verify environment**:

```bash
# Ensure venv is active
which python  # Should show .venv/bin/python

# Reinstall test dependencies
pip install -r requirements.txt
```

**Solution 2 - Run tests verbosely**:

```bash
# Get detailed output
pytest -v

# Run specific test
pytest tests/test_main.py::test_health_check -v

# Show print statements
pytest -s
```

**Solution 3 - Check test coverage**:

```bash
# Run with coverage report
pytest --cov=app --cov-report=term-missing

# Identify untested code
pytest --cov=app --cov-report=html
# Open htmlcov/index.html in browser
```

---

### Import Errors in Tests

**Problem**: `ModuleNotFoundError: No module named 'app'`

**Solution**: Ensure project root is in PYTHONPATH

```bash
# Run pytest from project root
cd /path/to/ml-platform-engineering-practicum
pytest

# Or set PYTHONPATH explicitly
export PYTHONPATH="${PYTHONPATH}:$(pwd)"
pytest
```

---

## API Server

### API Won't Start

**Problem**: `uvicorn app.main:app --reload` fails

**Common Causes**:

**1. Port Already in Use**:

```bash
# Error: Address already in use
# Kill process on port 8000
lsof -ti:8000 | xargs kill -9

# Or use different port
uvicorn app.main:app --reload --port 8001
```

**2. Module Not Found**:

```bash
# Error: ModuleNotFoundError: No module named 'app'
# Verify you're in project root
pwd  # Should show .../ml-platform-engineering-practicum

# Check directory structure
ls -la  # Should see app/ directory
```

**3. Model File Missing**:

```bash
# Error: FileNotFoundError: models/iris_classifier.skops
# Train model first
python train_model.py

# Verify model exists
ls -lh models/iris_classifier.skops
```

---

### API Returns 500 Errors

**Problem**: Requests to `/predict` return Internal Server Error

**Solution 1 - Check logs**:

```bash
# Run with debug logging
uvicorn app.main:app --reload --log-level debug

# Watch for error details in terminal
```

**Solution 2 - Test model loading**:

```bash
# Verify model loads correctly
python -c "from app.model import get_model; print(get_model())"

# Should output: <class 'sklearn.ensemble._forest.RandomForestClassifier'>
```

**Solution 3 - Check request format**:

```bash
# Correct format
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"features": [5.1, 3.5, 1.4, 0.2]}'

# Should return: {"prediction": 0, "probabilities": [...]}
```

---

## Docker

### Docker Build Fails

**Problem**: `docker build` exits with errors

**Common Issues**:

**1. Base Image Pull Fails**:

```bash
# Check Docker daemon is running
docker ps

# Pull base image manually
docker pull python:3.13-slim

# Retry build
docker build -t ml-platform-api:latest .
```

**2. File Not Found in Build**:

```bash
# Error: COPY failed: file not found
# Verify files exist
ls -la requirements.txt models/iris_classifier.skops

# Check .dockerignore isn't excluding needed files
cat .dockerignore
```

---

### Container Won't Start

**Problem**: `docker run` exits immediately

**Solution - Check logs**:

```bash
# Get container ID
docker ps -a

# View logs
docker logs <container-id>

# Run interactively to debug
docker run -it ml-platform-api:latest /bin/bash
```

---

### Trivy Scan Failures

**Problem**: Trivy finds HIGH/CRITICAL vulnerabilities in Docker image

**Cause**: Vulnerable packages in base image or Python dependencies.

**Solution**: See `docs/VULNERABILITY_REMEDIATION.md` for detailed workflow.

---

## Kubernetes

### Pod Stuck in Pending

**Problem**: `kubectl get pods` shows `Pending` status

**Solution**:

```bash
# Check why pending
kubectl describe pod <pod-name>

# Common causes:
# - Insufficient resources (check Events section)
# - Image pull errors (verify image exists)
# - Volume mount issues (check PV/PVC status)

# Check node resources
kubectl top nodes
```

---

### Image Pull Errors

**Problem**: `ErrImagePull` or `ImagePullBackOff`

**Solution**:

```bash
# Verify image exists locally (Minikube)
minikube image ls | grep ml-platform-api

# Load image to Minikube
minikube image load ml-platform-api:latest

# Verify image pull policy in deployment
kubectl get deployment ml-platform-api -o yaml | grep imagePullPolicy
# Should be: imagePullPolicy: Never (for local images)
```

---

### Service Not Accessible

**Problem**: Cannot access service via `minikube service ml-platform-api`

**Solution**:

```bash
# Check service exists
kubectl get svc

# Verify service type
kubectl get svc ml-platform-api -o yaml | grep type
# Should be: type: NodePort or LoadBalancer

# Get service URL
minikube service ml-platform-api --url

# Test directly
curl $(minikube service ml-platform-api --url)/health/ready
```

---

## Git & GitHub

### Commit Message Format Invalid

**Problem**: Pre-commit rejects commit message

**Solution**: Follow conventional commits format

```bash
# ✅ Valid formats
git commit -m "feat(api): add health check endpoint"
git commit -m "fix(model): resolve loading timeout"
git commit -m "docs(readme): update setup instructions"

# ❌ Invalid formats
git commit -m "Added feature"  # No type/scope
git commit -m "fix bug"         # Too vague
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`, `infra`

---

### Merge Conflicts

**Problem**: `git pull` shows merge conflicts

**Solution**:

```bash
# See conflicting files
git status

# Open file, resolve conflicts (between <<<<<<< and >>>>>>>)
# Then mark as resolved
git add <file>

# Continue merge
git merge --continue

# Or abort and retry
git merge --abort
```

---

## SonarCloud

### Quality Gate Failing

**Problem**: PR blocked by SonarCloud quality gate

**Common Issues**:

**1. Coverage Below 80%**:

```bash
# Check local coverage
pytest --cov=app --cov-report=term-missing

# Add tests for uncovered lines
# Re-run to verify improvement
```

**2. Code Duplication > 3%**:

```bash
# Refactor duplicated blocks into functions
# Extract common logic to reduce duplication
```

**3. Bugs/Vulnerabilities**:

```bash
# Click "Details" on SonarCloud check in PR
# Review specific issues
# Fix code based on recommendations
# Push changes → SonarCloud re-analyzes
```

---

## Security Scanning

### Trivy Finds Vulnerabilities

**Problem**: Container image has HIGH/CRITICAL vulnerabilities

**Solution**:

```bash
# See detailed report
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image ml-platform-api:latest

# Update base image
# In Dockerfile, change:
FROM python:3.13-slim  # Update to latest patch version

# Rebuild and rescan
docker build -t ml-platform-api:latest .
```

---

### Bandit Flags Security Issue

**Problem**: `bandit` identifies Python security vulnerability

**Solution**:

```bash
# Review specific issue
bandit -r app/

# Fix code (e.g., avoid shell=True, use parameterized queries)
# If false positive, add comment with justification:
# my_code()  # nosec B101 - False positive, input is sanitized
```

---

## Model Loading

### .skops File Not Found

**Problem**: `FileNotFoundError: models/iris_classifier.skops`

**Cause**: The model file hasn't been trained yet or was deleted.

**Solution**:

```bash
# Train model to generate .skops file
python train_model.py

# Verify file exists
ls -lh models/iris_classifier.skops

# Check SHA-256 hash (if metadata exists)
python -c "
import hashlib
with open('models/iris_classifier.skops', 'rb') as f:
    hash = hashlib.sha256(f.read()).hexdigest()
print(f'SHA-256: {hash}')
"
```

---

### Model Hash Mismatch

**Problem**: `SecurityError: Model hash mismatch!` or `ModelIntegrityError`

**Cause**: Model file was corrupted or manually modified, causing hash mismatch.

**Solution**: Retrain model or update hash

```bash
# Option 1: Retrain model (regenerates hash) - RECOMMENDED
python train_model.py

# Option 2: Update expected hash in code
# (Only if you trust the model file)
# Calculate new hash and update in app/model.py
```

**Prevention**: Never manually edit model files. Always retrain using `train_model.py`.

---

## CI/CD Issues

### CI/CD Job Failures

**Problem**: CI jobs fail unexpectedly

**Cause**: Code doesn't pass linting, tests, or security scans.

**Solution**:

```bash
# Run tests locally first
pytest -v

# Check code quality locally
black --check .
ruff check .
mypy app/

# View CI logs in GitHub Actions tab for specific error details
```

**Debugging steps**:

1. Check the GitHub Actions tab for the failed workflow
2. Click on the failed job to see detailed logs
3. Reproduce the failure locally using the commands above
4. Fix the issue and push again

---

### SonarCloud Failures

**Problem**: SonarCloud quality gate fails

**Cause**: Code quality metrics below threshold (coverage, code smells, duplications).

**Solution**:

1. Check SonarCloud dashboard for specific issues
2. Address code smells and duplications
3. Increase test coverage if below 80%

```bash
# Generate coverage report locally
pytest --cov=app --cov-report=html

# Open htmlcov/index.html to see coverage details
```

---

### Security Scan Failures

**Problem**: Trivy/Gitleaks/Semgrep finds vulnerabilities

**Cause**: Known vulnerabilities in dependencies or code patterns.

**Solution**: See `docs/VULNERABILITY_REMEDIATION.md` for detailed workflow.

---

## Getting Help

### Documentation

- **Quick Reference**: `docs/QUICK_REFERENCE.md` - Git commands, GitHub CLI, conventions
- **Security**: `docs/VULNERABILITY_REMEDIATION.md` - Vulnerability handling workflow
- **Contributing**: `CONTRIBUTING.md` - PR workflow, merge conflicts
- **Project Management**: `docs/PROJECT_MANAGEMENT.md` - GitHub Projects setup

### CI Logs

1. Go to GitHub Actions tab
2. Click on the failed workflow run
3. Click on the failed job
4. Expand the failed step to see detailed logs

### Common Resources

- **Python errors**: Check virtual environment activation and dependencies
- **Git errors**: See `docs/QUICK_REFERENCE.md` for common Git commands
- **Docker errors**: Check Docker daemon is running: `docker info`
- **Security findings**: See `docs/VULNERABILITY_REMEDIATION.md`

### Still Stuck?

1. Search existing GitHub issues for similar problems
2. Check the project documentation in `docs/`
3. Create a new issue using the Bug Report template

---

**Last Updated**: 2025-01-04
