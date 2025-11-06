# CLAUDE.md

Guidance for Claude Code working with this ML platform learning project.

## Quick Navigation

| Question | Answer | Details |
|----------|--------|---------|
| How do I run the API? | `uvicorn services.api.main:app --reload` | [QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md#api-server) |
| Run tests? | `pytest` | [CONTRIBUTING.md](CONTRIBUTING.md#testing-requirements) |
| Python version? | Python 3.13 + uv | [README.md](README.md#local-development-setup) |
| Commit format? | Conventional: `<type>(<scope>): <subject>` | [CONTRIBUTING.md](CONTRIBUTING.md#commit-guidelines) |
| Security tools? | pre-commit, Trivy, Syft, Cosign | [SECURITY.md](SECURITY.md) |

**Core**: [README.md](README.md) | [CONTRIBUTING.md](CONTRIBUTING.md) | [SECURITY.md](SECURITY.md) |
[ROADMAP.md](ROADMAP.md) | [QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)

**Specialized**: [Image Signing](docs/IMAGE_SIGNING.md) | [Model Security](docs/PICKLE_SECURITY.md) |
[AWS OIDC](docs/AWS_OIDC_SETUP.md) | [K8s Security](docs/KUBERNETES_SECURITY.md) | [SBOM](docs/SBOM_GENERATION.md)

---

## Project Context

Personal **learning project** building a production-grade ML platform from scratch. Focus on
hands-on experience with infrastructure, MLOps, and platform engineering. Uses production-like
workflows (issues, PRs, CI/CD) to build professional habits.

**Current Phase**: Phase 1 complete (FastAPI inference functional) → transitioning to Phase 2 (EKS & Kubernetes)

**Learning philosophy**: Document the "why" behind decisions, reflect on trade-offs, don't
just complete tasks—understand them deeply.

## Environment Requirements

**Critical**:

- **Python 3.13 + uv** (package manager)
- **.skops format** for models (NOT .pkl/.joblib - security requirement)
- **Pre-commit hooks** mandatory (blocks secrets, runs linters)

**Setup**: [README.md - Getting Started](README.md#getting-started)

## Essential Commands

```bash
# Development
uvicorn services.api.main:app --reload --host 0.0.0.0 --port 8000  # Run API server
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

**Complete command reference**: [docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)

## Code Standards

**Project-specific patterns**:

- **Model loading**: Singleton pattern in `app/model.py:get_model()`
- **Model security**: .skops format + SHA-256 verification (see [PICKLE_SECURITY.md](docs/PICKLE_SECURITY.md))
- **FastAPI**: Lifespan events, dependency injection, HTTPException with status codes
- **Testing**: 90% coverage target (SonarCloud gate: 80% minimum)

**Full standards**: [CONTRIBUTING.md](CONTRIBUTING.md)

- PEP 8 style (black formatter)
- Type hints required
- Docstrings for modules, classes, functions
- Conventional commits

## Workflow

**Branch naming**: `<type>/<description>` (e.g., `feature/add-mlflow`, `fix/api-timeout`)

**Commit format**: `<type>(<scope>): <subject>` (e.g., `feat(api): add health check endpoint`)

**Before pushing**:

1. Run tests: `pytest`
2. Run quality checks: `pre-commit run --all-files`
3. Optional: Run `/pre-push-review` Claude Code skill (shellcheck + actionlint)

**Complete workflow**: [CONTRIBUTING.md](CONTRIBUTING.md)

- Pull request process
- Code review checklist
- Merge strategy (squash merge)

### When to Create Issues

**Create issue first**:

- New features, non-trivial bugs, infrastructure changes
- Changes requiring discussion or architectural decisions
- Work taking multiple commits/sessions

**Skip issue**:

- Typo fixes, broken links, minor dependency updates
- Small refactoring, documentation improvements

## Security Requirements

**Never commit**:

- Secrets, API keys, credentials (pre-commit blocks: detect-secrets, Gitleaks)
- Binary files (images, models) - use Git LFS or external storage
- `.env` files with real credentials

**Model security**: .skops format + SHA-256 hash verification (NOT pickle/joblib - arbitrary code execution risk)

**Multi-layer scanning**:

- **Local**: Pre-commit hooks (detect-secrets, semgrep)
- **CI**: Trivy (filesystem + containers), Gitleaks (secrets), Semgrep (SAST), SonarCloud
- **Container**: Fail-fast on HIGH/CRITICAL vulnerabilities

**Full security policy**: [SECURITY.md](SECURITY.md)

- Vulnerability scanning (Trivy, Bandit)
- SBOM generation (Syft)
- Image signing (Cosign)
- Dependency updates (Dependabot)

## Project Structure

```text
ml-platform-engineering-practicum/
├── app/                    # FastAPI application
│   ├── main.py            # API endpoints
│   ├── model.py           # Model loading (singleton pattern)
│   └── schemas.py         # Pydantic models
├── services/api/models/    # Model artifacts (gitignored except metadata)
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

## Documentation Structure

**Core docs** (project root):

- `README.md` - Project overview, getting started, architecture
- `CONTRIBUTING.md` - Full PR workflow, merge conflicts, code standards
- `SECURITY.md` - Security practices, scanning tools, vulnerability management
- `ROADMAP.md` - Phase-by-phase implementation plan
- `CLAUDE.md` - This file (you are here)

**Specialized docs** (`docs/` directory):

- `QUICK_REFERENCE.md` - All commands (Docker, K8s, Python, AWS)
- `TROUBLESHOOTING.md` - Common issues and solutions
- `IMAGE_SIGNING.md` - Container image signing with Cosign
- `PICKLE_SECURITY.md` - Model deserialization security
- `AWS_OIDC_SETUP.md` - GitHub Actions AWS authentication
- `SONARCLOUD_QUALITY_STANDARDS.md` - Code quality metrics
- `KUBERNETES_SECURITY.md` - K8s security best practices
- `SBOM_GENERATION.md` - Software Bill of Materials
- `VULNERABILITY_REMEDIATION.md` - Trivy findings workflow
- `PROJECT_MANAGEMENT.md` - GitHub Projects setup
- `ALPINE_MIGRATION_ANALYSIS.md` - Docker base image analysis

## Forbidden Directories

**Ignore when exploring** (performance + irrelevant content):

- `.venv/` - Python virtual environment
- `.git/` - Git metadata
- `__pycache__/` - Python bytecode
- `.pytest_cache/` - Test cache
- `services/api/models/` - Binary ML artifacts (.skops files)
- `node_modules/` - If present (not currently in project)

## Quick Troubleshooting

**Common issues**:

- `ModuleNotFoundError` → Activate venv: `source .venv/bin/activate` (macOS/Linux) or `.venv\Scripts\activate` (Windows)
- Pre-commit fails → Install hooks: `pre-commit install`, then retry commit
- Tests fail → Check Python version: `python --version` (must be 3.13+)
- Model loading fails → Verify .skops file exists: `ls -lh services/api/models/iris_classifier.skops`

**Detailed troubleshooting**: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) (comprehensive guide for common issues)

---

**Last Updated**: 2025-11-05 (Enhanced with index layer for progressive disclosure)
