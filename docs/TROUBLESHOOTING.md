# Troubleshooting Guide

This guide provides solutions to common issues encountered when developing the ML Platform.

## Table of Contents

- [Model Errors](#model-errors)
- [Development Environment](#development-environment)
- [CI/CD Issues](#cicd-issues)
- [Docker Problems](#docker-problems)
- [Getting Help](#getting-help)

## Model Errors

### Model Not Found Error

**Problem**: `FileNotFoundError: Model file not found: models/iris_classifier.skops`

**Cause**: The model file hasn't been trained yet or was deleted.

**Solution**:

```bash
# Train the model first
python train_model.py

# Verify model files exist
ls -la models/
```

You should see:
- `iris_classifier.skops` - Trained model file
- `model_metadata.json` - Model metadata with hash

### Model Integrity Error

**Problem**: `ModelIntegrityError: Model file integrity verification failed`

**Cause**: Model file was corrupted or manually modified, causing hash mismatch.

**Solution**:

```bash
# Retrain the model (hash mismatch indicates corruption or manual edit)
python train_model.py

# If issue persists, check if model file was modified manually
git status models/
```

**Prevention**: Never manually edit model files. Always retrain using `train_model.py`.

## Development Environment

### Import Errors in Tests

**Problem**: `ModuleNotFoundError` when running pytest

**Cause**: Virtual environment not activated or dependencies not installed.

**Solution**:

```bash
# Ensure virtual environment is activated
source .venv/bin/activate  # or .venv\Scripts\activate on Windows

# Reinstall dependencies
uv pip install -r requirements.txt

# Verify installation
python -c "import fastapi; import sklearn; print('OK')"
```

### Port Already in Use

**Problem**: `Address already in use` when running uvicorn

**Cause**: Another process is using port 8000.

**Solution**:

```bash
# Find process using port 8000
lsof -i :8000  # macOS/Linux
netstat -ano | findstr :8000  # Windows

# Kill the process or use a different port
uvicorn app.main:app --reload --port 8001
```

**Alternative**: Use a different port for development:

```bash
uvicorn app.main:app --reload --port 8001
```

### Pre-commit Hook Failures

**Problem**: Pre-commit hooks fail on commit

**Cause**: Code doesn't meet formatting/linting standards or hook versions are outdated.

**Solution**:

```bash
# Run pre-commit manually to see detailed errors
pre-commit run --all-files

# Auto-fix formatting issues
black .
ruff check . --fix

# Update hook versions if needed
pre-commit autoupdate
```

**Common fixes**:
- **Black formatting**: Run `black .` to auto-format
- **Ruff linting**: Run `ruff check . --fix` to auto-fix
- **Detect-secrets**: Review flagged files, add to `.secrets.baseline` if false positive
- **Semgrep**: Review security findings, fix or add `# nosemgrep` with justification

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

### Security Scan Failures

**Problem**: Trivy/Gitleaks/Semgrep finds vulnerabilities

**Cause**: Known vulnerabilities in dependencies or code patterns.

**Solution**: See `docs/VULNERABILITY_REMEDIATION.md` for detailed workflow.

## Docker Problems

### Docker Build Failures

**Problem**: Docker image build fails

**Cause**: Dockerfile syntax errors, missing dependencies, or network issues.

**Solution**:

```bash
# Build with verbose output
docker build -t ml-platform-api:latest . --progress=plain

# Check Dockerfile syntax
docker build --check -t ml-platform-api:latest .

# Clean build cache if needed
docker builder prune
```

**Common issues**:
- **Base image pull failure**: Check network connection, try again
- **Dependency installation failure**: Check requirements.txt syntax
- **COPY failures**: Ensure files exist in build context

### Trivy Scan Failures

**Problem**: Trivy finds HIGH/CRITICAL vulnerabilities in Docker image

**Cause**: Vulnerable packages in base image or Python dependencies.

**Solution**:

```bash
# Scan image locally
trivy image ml-platform-api:latest --severity HIGH,CRITICAL

# For detailed remediation steps, see:
```

See `docs/VULNERABILITY_REMEDIATION.md` for the complete vulnerability handling workflow.

## Getting Help

### Documentation

- **Quick Reference**: `docs/QUICK_REFERENCE.md` - Git commands, GitHub CLI, conventions
- **Security**: `docs/VULNERABILITY_REMEDIATION.md` - Vulnerability handling workflow
- **Contributing**: `docs/CONTRIBUTING.md` - PR workflow, merge conflicts
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
