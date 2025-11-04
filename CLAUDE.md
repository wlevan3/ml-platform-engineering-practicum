# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **personal learning project** building a production-grade ML platform from scratch. The goal is
hands-on experience with infrastructure, MLOps, and platform engineering practices. The project follows
production-like workflows (issues, PRs, CI/CD) to build professional engineering habits.

**Current Phase**: Foundation & Setup (Phase 1) - Python ML service is functional, infrastructure (EKS,
Terraform) coming in Phase 2+.

## Learning Focus

This is a **learning project**, not a production service. Key goals:

- Build professional engineering habits (PRs, code review, CI/CD)
- Gain hands-on experience with ML infrastructure
- Document learnings and design decisions (use Learning Reflection issue template)
- Practice trade-off analysis and architectural thinking

**Development philosophy**:

- Consider production best practices (even for a learning project)
- Document the "why" behind decisions
- Reflect on trade-offs and alternatives
- Don't just complete tasks—understand them deeply
- After creating a PR, monitor CI checks: `gh pr checks $PR_NUMBER --watch`. Once complete, review any automated PR comments and address them

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

# Train model (creates models/iris_classifier.skops and metadata)
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
- **Security scanning** - Multiple tools for comprehensive coverage (see Security section for details)
- **SBOM generation** - Creates Software Bill of Materials (SPDX + CycloneDX formats) for Docker images and Python app

Jobs with conditionals (`if: hashFiles()`) will show as "skipped" in summary when their files don't exist.

**Note**: For comprehensive security scanning details (Trivy, Gitleaks, Semgrep) and vulnerability handling, see the **Security** section below.

### Docker

```bash
# Build image
docker build -t ml-platform-api:latest .

# Run container
docker run -p 8000:8000 ml-platform-api:latest

# Scan for vulnerabilities (local)
trivy image ml-platform-api:latest --severity HIGH,CRITICAL

# Build and scan multi-stage targets
docker build --target builder -t ml-platform-api:builder .
docker build --target runtime -t ml-platform-api:runtime .
trivy image ml-platform-api:builder --severity HIGH,CRITICAL
trivy image ml-platform-api:runtime --severity HIGH,CRITICAL
```

### SBOM (Software Bill of Materials)

SBOMs provide a complete inventory of software components for vulnerability management and compliance.
See [docs/SBOM_GENERATION.md](./docs/SBOM_GENERATION.md) for comprehensive documentation.

```bash
# Install Syft (required for local SBOM generation)
brew install syft  # macOS
# OR
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# Verify installation
syft version

# Generate SBOM for Docker image
syft ml-platform-api:latest -o spdx-json --file sbom-docker-spdx.json
syft ml-platform-api:latest -o cyclonedx-json --file sbom-docker-cyclonedx.json

# Generate SBOM for Python application
syft dir:. -o spdx-json --file sbom-python-spdx.json
syft dir:. -o cyclonedx-json --file sbom-python-cyclonedx.json

# View SBOM in terminal (human-readable)
syft ml-platform-api:latest

# Scan SBOM for vulnerabilities with Grype
brew install grype  # macOS
grype sbom:sbom-docker-cyclonedx.json --severity HIGH,CRITICAL
```

**CI/CD Integration**: SBOMs are automatically generated in CI and uploaded as artifacts (90-day retention).
Access them from the Actions tab → Workflow run → Artifacts section.

## Troubleshooting

### Common Issues

#### Model Not Found Error

**Problem**: `FileNotFoundError: Model file not found: models/iris_classifier.skops`

**Solution**:
```bash
# Train the model first
python train_model.py

# Verify model files exist
ls -la models/
```

#### Model Integrity Error

**Problem**: `ModelIntegrityError: Model file integrity verification failed`

**Solution**:
```bash
# Retrain the model (hash mismatch indicates corruption or manual edit)
python train_model.py

# If issue persists, check if model file was modified manually
git status models/
```

#### Pre-commit Hook Failures

**Problem**: Pre-commit hooks fail on commit

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

#### CI/CD Job Failures

**Problem**: CI jobs fail unexpectedly

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

#### Docker Build Failures

**Problem**: Docker image build fails

**Solution**:
```bash
# Build with verbose output
docker build -t ml-platform-api:latest . --progress=plain

# Check Dockerfile syntax
docker build --check -t ml-platform-api:latest .

# Clean build cache if needed
docker builder prune
```

#### Import Errors in Tests

**Problem**: `ModuleNotFoundError` when running pytest

**Solution**:
```bash
# Ensure virtual environment is activated
source .venv/bin/activate  # or .venv\Scripts\activate on Windows

# Reinstall dependencies
uv pip install -r requirements.txt

# Verify installation
python -c "import fastapi; import sklearn; print('OK')"
```

#### Port Already in Use

**Problem**: `Address already in use` when running uvicorn

**Solution**:
```bash
# Find process using port 8000
lsof -i :8000  # macOS/Linux
netstat -ano | findstr :8000  # Windows

# Kill the process or use a different port
uvicorn app.main:app --reload --port 8001
```

### Getting Help

- **Documentation**: Check `docs/` directory for detailed guides
- **CI logs**: GitHub Actions tab → Failed workflow → Job details
- **Security issues**: See `docs/VULNERABILITY_REMEDIATION.md`
- **Git issues**: See `docs/QUICK_REFERENCE.md` for common commands

## Commit and PR Workflow

### Branch Naming

```text
<type>/<short-description>
```

Types: `feature/`, `fix/`, `infra/`, `docs/`, `refactor/`, `ci/`

Example: `feature/add-mlflow-integration`

### Commit Format (Conventional Commits)

```text
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

#### Handling Merge Conflicts

If your branch has conflicts with `main`:

```bash
# Update your local main branch
git checkout main
git pull origin main

# Switch back to feature branch
git checkout your-feature-branch

# Rebase on latest main (preferred for clean history)
git rebase main

# If conflicts occur, resolve them in your editor
# Then continue rebase
git add <resolved-files>
git rebase --continue

# Force push (rebase rewrites history)
git push --force-with-lease origin your-feature-branch

# Alternative: Merge (creates merge commit)
git merge main
git push origin your-feature-branch
```

**Tip**: Use `--force-with-lease` instead of `--force` to prevent overwriting others' work.

#### When to Create Issues vs. Direct Changes

**Create an issue first** when:
- Implementing new features (use Feature Request template)
- Fixing non-trivial bugs (use Bug Report template)
- Making infrastructure changes (use Infrastructure Change template)
- Documenting learning reflections (use Learning Reflection template)
- Changes require discussion or architectural decisions
- Work will take multiple commits or sessions

**Skip issue creation** for:
- Typo fixes in documentation
- Updating dependencies (minor version bumps)
- Fixing broken links
- Small refactoring with no functional changes
- Documentation improvements (grammar, formatting)

**Workflow**:
```bash
# For issues: Create issue → Create branch → Make changes → Create PR → Link issue
# For direct changes: Create branch → Make changes → Create PR
```

### Before Creating PRs

Run the `pre-push-review` skill (Claude Code skill) to automatically check shell scripts and GitHub Actions:

```bash
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

```text
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
│   ├── iris_classifier.skops   # Trained model (skops format)
│   └── model_metadata.json     # Model metadata
├── tests/                   # Test suite
│   └── test_api.py         # FastAPI endpoint tests
├── docs/                    # Documentation
│   ├── PROJECT_MANAGEMENT.md
│   ├── QUICK_REFERENCE.md
│   └── ALPINE_MIGRATION_ANALYSIS.md
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

#### Model Security (Secure Deserialization)

Models are serialized using **skops.io** (v0.13.0+), which provides pickle-free deserialization to address CWE-502:

- **Execution safety**: skops.io prevents arbitrary code execution during deserialization
- **Source control**: Models trained locally via `train_model.py` in controlled environment
- **No user input**: Model path is hardcoded (`models/iris_classifier.skops`)
- **Integrity verification**: SHA-256 hash verification detects tampering
  - Hash generated during training and stored in `model_metadata.json`
  - Hash verified before loading in `app/model.py`
  - Raises `ModelIntegrityError` if file corrupted or modified

**Security Model**:

- **Hash verification** = File integrity (detects tampering/corruption)
- **skops.io** = Execution safety (prevents code execution, addresses CWE-502)
- These protections are complementary, not redundant

**Phase 3 migration**: Will integrate with MLflow Model Registry using custom PyFunc wrapper.
See `docs/PICKLE_SECURITY.md` for comprehensive security analysis and migration decisions.

### Security

#### Secret Management

- **No secrets in code** - Use environment variables or AWS Secrets Manager
- Pre-commit hook `detect-secrets` scans for accidental credential commits
- Pre-commit hook `semgrep` scans for security vulnerabilities (custom ruleset in `.semgrep.yml`)
- CI includes Gitleaks (secrets), Trivy (filesystem + container images), Semgrep (comprehensive SAST rulesets)
- **Container security** - Trivy scans Docker images with fail-fast on HIGH/CRITICAL vulnerabilities
  - Scans OS packages, Python dependencies, and Dockerfile best practices
  - Separate scans for builder and runtime stages
  - Results uploaded to GitHub Security tab
- **Image signing** - Cosign signs container images with cryptographic signatures
  - Keyless signing via GitHub Actions OIDC (no key management overhead)
  - Signatures stored in OCI registry alongside images
  - Transparency log records all signatures in Rekor
  - Signatures verified before deployment to prevent tampering
  - Supports Kubernetes admission controllers (Sigstore Policy Controller, Kyverno)
- GitHub Actions use **pinned SHA hashes** for security scanning actions

#### Security Scanning (Multi-Layer Approach)

The project uses multiple security scanning tools for defense in depth:

1. **Pre-commit Hooks** (local development)
   - `detect-secrets` - Prevents accidental credential commits
   - `semgrep` - SAST scanning with custom ruleset (`.semgrep.yml`)

2. **CI Pipeline** (automated on PRs/pushes)
   - **Trivy** - Filesystem + container image scanning
     - Scans OS packages, Python dependencies, and Dockerfile best practices
     - Separate scans for builder and runtime stages
     - Fail-fast on HIGH/CRITICAL vulnerabilities
     - Results uploaded to GitHub Security tab
   - **Gitleaks** - Comprehensive secret detection
   - **Semgrep** - Advanced SAST with comprehensive rulesets
   - **SonarCloud** - Code quality and security analysis

3. **GitHub Actions Security**
   - Security scanning actions use **pinned SHA hashes** (prevents supply chain attacks)

#### Vulnerability Management

- **Vulnerability handling**: See `docs/VULNERABILITY_REMEDIATION.md` for detailed workflow on handling Trivy findings, including remediation steps, `.trivyignore` usage, and debugging
- **SBOM tracking**: See `docs/SBOM_GENERATION.md` for dependency inventory and compliance

**Image signing**: See `docs/IMAGE_SIGNING.md` for container image signing implementation and verification.

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

## Documentation Reference

For detailed guidance on project workflows and management, refer to:

- **docs/PROJECT_MANAGEMENT.md** - Complete guide to GitHub Projects setup, issue
  templates, custom fields, automation workflows, and project board configuration
- **docs/QUICK_REFERENCE.md** - Quick reference for Git commands, GitHub CLI, commit
  conventions, project field values, and useful links
- **docs/VULNERABILITY_REMEDIATION.md** - Workflow for handling security vulnerabilities
  detected by Trivy, including remediation steps, .trivyignore usage, and debugging
- **docs/SBOM_GENERATION.md** - Software Bill of Materials (SBOM) generation using Syft.
  Covers SBOM formats (SPDX, CycloneDX), compliance requirements (EO 14028, EU CRA),
  CI/CD integration, local generation commands, and vulnerability scanning workflows
- **docs/PICKLE_SECURITY.md** - Model deserialization security analysis and skops.io migration
- **docs/ALPINE_MIGRATION_ANALYSIS.md** - Alpine Linux Docker base image investigation findings
  and decision analysis. Documents why Alpine is not optimal for scientific Python workloads
  despite security benefits. Key learning: application dependencies dominate image size for ML platforms.
- **docs/AWS_OIDC_SETUP.md** - AWS OIDC authentication setup for GitHub Actions. Explains
  how to configure OpenID Connect between GitHub Actions and AWS IAM for secure,
  credential-free deployments using temporary tokens instead of long-lived access keys.
- **docs/IMAGE_SIGNING.md** - Container image signing implementation with Cosign. Documents
  keyless signing via GitHub Actions OIDC, signature verification procedures, Kubernetes
  admission controller integration (Sigstore Policy Controller, Kyverno), and local testing workflows.

## Issue Templates and GitHub Projects

The project uses **GitHub Projects** for tracking work:

- **Issue templates** for features, bugs, infrastructure changes, and learning reflections
- **Project boards** for status tracking (Backlog → In Progress → Done)
- **Component views** for organizing by platform component
- **Roadmap view** for timeline visualization

See docs/PROJECT_MANAGEMENT.md for complete setup instructions.
