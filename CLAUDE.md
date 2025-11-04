# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this repository.

## Project Context

Personal **learning project** building a production-grade ML platform from scratch. Focus on hands-on experience with infrastructure, MLOps, and platform engineering. Uses production-like workflows (issues, PRs, CI/CD) to build professional habits.

**Current Phase**: Foundation & Setup (Phase 1) - FastAPI ML inference service (Iris classifier) is functional. Infrastructure (EKS, Terraform) coming in Phase 2+.

**Learning philosophy**: Document the "why" behind decisions, reflect on trade-offs, don't just complete tasks—understand them deeply.

## Development Environment

IMPORTANT: This project uses **Python 3.13** with **uv** package manager.

IMPORTANT: Model files use **.skops format** (not .joblib or .pkl) for secure deserialization.

```bash
# Setup
uv venv .venv --python 3.13
source .venv/bin/activate  # Windows: .venv\Scripts\activate
uv pip install -r requirements.txt
python train_model.py  # Creates models/iris_classifier.skops + metadata

# Alternative: standard venv (if uv unavailable)
python3.13 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
```

## Essential Commands

```bash
# Development
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000  # Run API server
python train_model.py                                      # Train model
pytest                                                     # Run tests
pytest -v --cov=app --cov-report=term-missing             # Tests with coverage

# Code quality (YOU MUST run before pushing)
black .                   # Format code
ruff check . --fix        # Lint and auto-fix
mypy app/                 # Type checking
pre-commit run --all-files  # Run all pre-commit hooks

# Pre-commit setup
pre-commit install        # Install hooks (one-time)

# Docker
docker build -t ml-platform-api:latest .                  # Build image
docker run -p 8000:8000 ml-platform-api:latest           # Run container
trivy image ml-platform-api:latest --severity HIGH,CRITICAL  # Scan vulnerabilities

# SBOM generation
syft ml-platform-api:latest -o spdx-json --file sbom-docker-spdx.json
```

## Code Standards

### Python

- **Style**: PEP 8 via black (line length: 88)
- **Type hints**: Required for all function signatures
- **Docstrings**: Required for modules, classes, public functions (Google style)
- **Exceptions**: Use specific exceptions, never bare `except:`
- **Validation**: Pydantic models for FastAPI schemas

### FastAPI Patterns

- **Singleton pattern** for model loading → `app/model.py:get_model()`
- **Lifespan events** for startup/shutdown → `app/main.py:lifespan()`
- **Dependency injection** for shared resources
- **HTTPException** for errors with proper status codes
- **Response models** for all endpoints

### Testing

- **Location**: `tests/` directory, files named `test_*.py`
- **Framework**: pytest with fixtures
- **API testing**: FastAPI `TestClient`
- **Coverage**: 80%+ target (configured in pytest.ini)

## Workflow

### Branch Naming

```
<type>/<short-description>
```

Types: `feature/`, `fix/`, `infra/`, `docs/`, `refactor/`, `ci/`

Example: `feature/add-mlflow-integration`

### Commit Format

Follow Conventional Commits:

```
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `infra`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`

Examples:
- `feat(model-registry): add MLflow integration`
- `fix(api): resolve prediction timeout issue`
- `infra(eks): upgrade cluster to v1.28`

### Pull Request Checklist

YOU MUST complete before pushing:

1. Run `pytest` - all tests pass
2. Run `pre-commit run --all-files` - all hooks pass
3. Run `/pre-push-review` (Claude Code skill) - shellcheck + actionlint

After creating PR:
```bash
gh pr checks $PR_NUMBER --watch  # Monitor CI
```

Then review automated PR comments and address them.

### When to Create Issues

**Create issue first**:
- New features, non-trivial bugs, infrastructure changes
- Changes requiring discussion or architectural decisions
- Work taking multiple commits/sessions

**Skip issue**:
- Typo fixes, broken links, minor dependency updates
- Small refactoring, documentation improvements

## Security

IMPORTANT: Never commit secrets - pre-commit hooks (detect-secrets, Gitleaks) will block.

IMPORTANT: Model security uses **skops.io** format (.skops) with SHA-256 hash verification.

**Multi-layer scanning**:
- **Local**: Pre-commit hooks (detect-secrets, semgrep)
- **CI**: Trivy (filesystem + containers), Gitleaks (secrets), Semgrep (SAST), SonarCloud
- **Container**: Fail-fast on HIGH/CRITICAL vulnerabilities

See `docs/SECURITY.md` for detailed security practices.

## Project Structure

```
ml-platform-engineering-practicum/
├── app/                    # FastAPI application
│   ├── main.py            # API endpoints
│   ├── model.py           # Model loading (singleton pattern)
│   └── schemas.py         # Pydantic models
├── models/                 # Model artifacts (gitignored except metadata)
│   ├── iris_classifier.skops   # Trained model (skops format)
│   └── model_metadata.json     # Model metadata + hash
├── tests/                  # Test suite
│   └── test_api.py        # FastAPI tests
├── docs/                   # Documentation
├── train_model.py         # Model training script
├── requirements.txt       # Python dependencies
├── Dockerfile             # Container image
└── .pre-commit-config.yaml  # Pre-commit hooks
```

## CI/CD Pipeline

Runs on PRs and pushes to `main`:
- Markdown linting, Python linting (Black, Ruff)
- Tests with coverage → SonarCloud
- Security: Trivy, Gitleaks, Semgrep
- Docker image build + scan (builder + runtime stages)
- SBOM generation (SPDX + CycloneDX)

Jobs are **conditional** based on file existence. Skipped jobs show in summary.

## Detailed Documentation

For comprehensive guides, see:

- **docs/CONTRIBUTING.md** - Full PR workflow, merge conflicts, code standards
- **docs/TROUBLESHOOTING.md** - Common issues and solutions
- **docs/SECURITY.md** - Security practices, scanning tools, vulnerability management
- **docs/VULNERABILITY_REMEDIATION.md** - Trivy findings workflow
- **docs/SBOM_GENERATION.md** - Software Bill of Materials
- **docs/PICKLE_SECURITY.md** - Model deserialization security
- **docs/PROJECT_MANAGEMENT.md** - GitHub Projects setup
- **docs/QUICK_REFERENCE.md** - Git commands, conventions
- **docs/ALPINE_MIGRATION_ANALYSIS.md** - Docker base image analysis
- **docs/AWS_OIDC_SETUP.md** - GitHub Actions AWS auth
- **docs/IMAGE_SIGNING.md** - Container image signing with Cosign
