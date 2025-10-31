# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **personal learning project** building a production-grade ML platform from scratch. The goal is hands-on experience with infrastructure, MLOps, and platform engineering practices. The project follows production-like workflows (issues, PRs, CI/CD) to build professional engineering habits.

**Current Phase**: Foundation & Setup (Phase 1) - Python ML service is functional, infrastructure (EKS, Terraform) coming in Phase 2+.

## Architecture

### Current Implementation

The project currently has a **simple ML inference service** as a foundation:

- **FastAPI application** (`app/`) - REST API for iris flower classification
  - `main.py` - API endpoints (health, prediction, model info)
  - `model.py` - Model loading and inference logic (singleton pattern)
  - `schemas.py` - Pydantic models for request/response validation
- **Model training** (`train_model.py`) - Trains RandomForest classifier on Iris dataset
- **Model artifacts** (`models/`) - Serialized model (joblib) and metadata (JSON)

### Planned Architecture (Phases 2-7)

- **AWS EKS** - Kubernetes cluster for ML workloads
- **MLflow** - Model registry and experiment tracking
- **Terraform** - Infrastructure as Code (no terraform/ directory yet)
- **Observability** - Prometheus, Grafana, ELK stack
- **Feature Store** - Feast (planned)

## Development Commands

### Python Development

**Important**: This project uses **Python 3.13** with **uv** for package management and a **.venv** virtual environment.

```bash
# Setup virtual environment (Python 3.13 with uv)
uv venv .venv --python 3.13
source .venv/bin/activate  # or .venv\Scripts\activate on Windows
uv pip install -r requirements.txt

# Alternative: Standard venv (if uv not available)
python3.13 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Train model (creates models/iris_classifier.joblib and metadata)
python train_model.py

# Run FastAPI server locally
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Run tests with coverage
pytest                           # Run all tests
pytest tests/test_api.py         # Run specific test file
pytest -v                        # Verbose output
pytest -k "test_health"          # Run tests matching pattern

# Code quality
black .                          # Format code
black --check .                  # Check formatting without changes
ruff check .                     # Lint code
ruff check . --fix               # Auto-fix linting issues
mypy app/                        # Type checking
```

### Pre-commit Hooks

```bash
# Install hooks
pre-commit install

# Run manually on all files
pre-commit run --all-files

# Run specific hook
pre-commit run black --all-files
```

### CI/CD

The CI pipeline (`.github/workflows/ci.yml`) runs automatically on PRs and pushes to `main`. It includes:

- **Markdown linting** - Always runs
- **Terraform validation** - Only if `terraform/` exists
- **Kubernetes validation** - Only if `k8s/` exists
- **Python linting** (Black, Ruff) - Only if `.py` files exist
- **Python tests with coverage** - Only if `.py` files exist
- **SonarCloud analysis** - Code quality and security (requires tests)
- **Security scanning** - Trivy (filesystem), Gitleaks (secrets), Semgrep (SAST)

Jobs with conditionals (`if: hashFiles()`) will show as "skipped" in summary when their files don't exist.

### Docker

```bash
# Build image
docker build -t ml-platform-api:latest .

# Run container
docker run -p 8000:8000 ml-platform-api:latest
```

## Commit and PR Workflow

### Branch Naming

```
<type>/<short-description>
```

Types: `feature/`, `fix/`, `infra/`, `docs/`, `refactor/`, `ci/`

Example: `feature/add-mlflow-integration`

### Commit Format (Conventional Commits)

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `infra`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`

Examples:
- `feat(model-registry): add MLflow integration`
- `fix(api): resolve prediction timeout issue`
- `infra(eks): upgrade cluster to v1.28`
- `docs(readme): add architecture diagram`

### Pull Request Process

1. Create feature branch from `main`
2. Make changes with atomic commits
3. Run tests locally: `pytest` and `pre-commit run --all-files`
4. Push and create PR using template
5. Self-review your changes
6. Ensure CI passes
7. **Squash merge** to `main` (keeps history clean)

### Before Creating PRs

Run the `pre-push-review` skill (Claude Code skill) to automatically check shell scripts and GitHub Actions:

```
/pre-push-review
```

This runs `shellcheck` on `.sh/.bash` files and `actionlint` on `.github/workflows/*.yml` files in your changes.

## Code Standards

### Python

- Follow **PEP 8** via `black` (line length: 88)
- Use **type hints** for function signatures
- **Docstrings** for modules, classes, and public functions
- Exception handling with specific exceptions, never bare `except:`
- Pydantic models for data validation (FastAPI schemas)

### FastAPI Patterns

- **Singleton pattern** for model loading (see `app/model.py:get_model()`)
- **Lifespan events** for startup/shutdown logic (see `app/main.py:lifespan()`)
- **Dependency injection** for shared resources
- **HTTPException** for error responses with proper status codes
- **Response models** for all endpoints (type safety and auto-docs)

### Testing

- Tests in `tests/` directory
- Use `pytest` fixtures for shared setup
- FastAPI `TestClient` for API testing (see `tests/test_api.py`)
- Coverage target: 80%+ (configured in `pytest.ini`)
- Test file naming: `test_*.py`

### Infrastructure (Future)

When Terraform is added:
- Descriptive resource names with consistent prefixes
- Tag all AWS resources: `Project`, `Environment`, `ManagedBy`
- Use variables for reusable values
- Organize by service/component
- Always review `terraform plan` before apply

## Project Structure

```
ml-platform-engineering-practicum/
├── .github/
│   ├── workflows/           # CI/CD pipelines
│   │   ├── ci.yml          # Main CI pipeline
│   │   ├── codeql.yml      # Security scanning
│   │   └── resolve-comments.yml  # Auto-resolve outdated PR comments
│   └── PULL_REQUEST_TEMPLATE.md
├── app/                     # FastAPI application
│   ├── __init__.py         # Package init with version
│   ├── main.py             # API endpoints
│   ├── model.py            # Model loading/inference (singleton)
│   └── schemas.py          # Pydantic models
├── models/                  # Model artifacts (gitignored except metadata)
│   ├── iris_classifier.joblib  # Trained model
│   └── model_metadata.json     # Model metadata
├── tests/                   # Test suite
│   └── test_api.py         # FastAPI endpoint tests
├── docs/                    # Documentation
│   ├── PROJECT_MANAGEMENT.md
│   └── QUICK_REFERENCE.md
├── train_model.py          # Model training script
├── requirements.txt        # Python dependencies
├── pytest.ini              # Pytest and coverage config
├── Dockerfile              # Container image
├── .pre-commit-config.yaml # Pre-commit hooks
└── README.md               # Project overview
```

**Future additions** (Phases 2+):
- `terraform/` - Infrastructure as Code
- `k8s/` - Kubernetes manifests
- `scripts/` - Automation scripts

## Important Notes

### Model Management

- Models are **trained locally** via `train_model.py` (for now)
- Model files are **gitignored** (too large), only metadata is tracked
- Model loading uses **singleton pattern** to avoid reloading on each request
- Metadata in `models/model_metadata.json` includes version, accuracy, features, classes

### Security

- **No secrets in code** - Use environment variables or AWS Secrets Manager
- Pre-commit hook `detect-secrets` scans for accidental credential commits
- CI includes Gitleaks (secrets), Trivy (vulnerabilities), Semgrep (SAST)
- GitHub Actions use **pinned SHA hashes** for security scanning actions

### CI/CD Behavior

- CI jobs are **conditional** based on file existence (e.g., Python jobs only run if `.py` files exist)
- The `summary` job always runs (`if: always()`) and shows status of all jobs, including "skipped"
- SonarCloud requires test coverage XML (`coverage.xml` uploaded as artifact)

### Branch Protection

- `main` branch is protected:
  - Requires pull request
  - Requires conversation resolution
  - No force pushes
  - No direct commits

## Issue Templates and GitHub Projects

The project uses **GitHub Projects** for tracking work:

- **Issue templates** for features, bugs, infrastructure changes, and learning reflections
- **Project boards** for status tracking (Backlog → In Progress → Done)
- **Component views** for organizing by platform component
- **Roadmap view** for timeline visualization

See [docs/PROJECT_MANAGEMENT.md](docs/PROJECT_MANAGEMENT.md) for details.

## Learning Focus

This is a **learning project**, not a production service. Key goals:

- Build professional engineering habits (PRs, code review, CI/CD)
- Gain hands-on experience with ML infrastructure
- Document learnings and design decisions (use Learning Reflection issue template)
- Practice trade-off analysis and architectural thinking

When making changes:
- Consider production best practices (even for a learning project)
- Document the "why" behind decisions
- Reflect on trade-offs and alternatives
- Don't just complete tasks—understand them deeply
