# CLAUDE.md

Guidance for Claude Code working with this ML platform learning project.

## 🎯 Quick Navigation (Index)

**Common Questions** → Direct Answers:

- **"How do I run the API?"** → `uvicorn app.main:app --reload` (details: [QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md#api-server))
- **"How do I run tests?"** → `pytest` (full options: [CONTRIBUTING.md](CONTRIBUTING.md#testing-requirements))
- **"What Python version?"** → **Python 3.13 + uv** (setup: [README.md](README.md#local-development-setup))
- **"How do I commit code?"** → **Conventional commits** `<type>(<scope>): <subject>` (guide: [CONTRIBUTING.md](CONTRIBUTING.md#commit-guidelines))
- **"Security scanning tools?"** → pre-commit, Trivy, Syft, Cosign (details: [SECURITY.md](SECURITY.md))

**By Task**:

- **Setup/Getting Started** → [README.md](README.md#getting-started) (Prerequisites, local dev, Docker, K8s)
- **All Commands** → [docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md) (Docker, K8s, Python, testing, security)
- **Workflow & Standards** → [CONTRIBUTING.md](CONTRIBUTING.md) (Branch strategy, PR process, code quality)
- **Security Practices** → [SECURITY.md](SECURITY.md) (Scanning, vulnerabilities, SBOM, image signing)
- **Project Roadmap** → [ROADMAP.md](ROADMAP.md) (Phase-by-phase implementation plan)

**Specialized Topics**:

- Image signing (Cosign) → [docs/IMAGE_SIGNING.md](docs/IMAGE_SIGNING.md)
- Model security (pickle) → [docs/PICKLE_SECURITY.md](docs/PICKLE_SECURITY.md)
- AWS OIDC setup → [docs/AWS_OIDC_SETUP.md](docs/AWS_OIDC_SETUP.md)
- SonarCloud quality → [docs/SONARCLOUD_QUALITY_STANDARDS.md](docs/SONARCLOUD_QUALITY_STANDARDS.md)
- Kubernetes security → [docs/KUBERNETES_SECURITY.md](docs/KUBERNETES_SECURITY.md)
- SBOM generation → [docs/SBOM_GENERATION.md](docs/SBOM_GENERATION.md)

---

## Project Context

- **Type**: Learning project (production-grade ML platform)
- **Current Phase**: Phase 1 complete (FastAPI inference functional) → transitioning to Phase 2 (EKS & Kubernetes)
- **Philosophy**: Document "why" behind decisions, understand deeply (not just complete tasks)
- **Workflow**: Production practices (issues, PRs, CI/CD) to build professional habits

## Environment Requirements

**Critical**:

- **Python 3.13 + uv** (package manager)
- **.skops format** for models (NOT .pkl/.joblib - security requirement)
- **Pre-commit hooks** mandatory (blocks secrets, runs linters)

**Setup**: [README.md - Getting Started](README.md#getting-started)

## Essential Commands

```bash
# Development
uvicorn app.main:app --reload  # Run API server
pytest                          # Run all tests
pytest --cov=app               # With coverage

# Quality & Security
pre-commit run --all-files     # Run all quality checks
pre-commit install             # Install git hooks (first time)

# Before Push
pytest && pre-commit run --all-files
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
3. Optional: Run pre-push-review Claude skill

**Complete workflow**: [CONTRIBUTING.md](CONTRIBUTING.md)

- Pull request process
- Code review checklist
- Merge strategy (squash merge)

## Security

**Never commit**:

- Secrets, API keys, credentials (pre-commit blocks: detect-secrets, Gitleaks)
- Binary files (images, models) - use Git LFS or external storage
- `.env` files with real credentials

**Model security**: .skops format + SHA-256 hash verification (NOT pickle/joblib - arbitrary code execution risk)

**Full security policy**: [SECURITY.md](SECURITY.md)

- Vulnerability scanning (Trivy, Bandit)
- SBOM generation (Syft)
- Image signing (Cosign)
- Dependency updates (Dependabot)

## Documentation Structure

**Core docs** (project root):

- `README.md` - Project overview, getting started, architecture
- `CONTRIBUTING.md` - Workflow, standards, PR process (622 lines)
- `SECURITY.md` - Security practices, scanning tools (150 lines)
- `ROADMAP.md` - Phase-by-phase implementation plan
- `CLAUDE.md` - This file (you are here)

**Specialized docs** (`docs/` directory):

- `QUICK_REFERENCE.md` - All commands (Docker, K8s, Python, AWS)
- `IMAGE_SIGNING.md` - Container image signing with Cosign
- `PICKLE_SECURITY.md` - Model deserialization security
- `AWS_OIDC_SETUP.md` - GitHub Actions AWS authentication
- `SONARCLOUD_QUALITY_STANDARDS.md` - Code quality metrics
- `KUBERNETES_SECURITY.md` - K8s security best practices
- `SBOM_GENERATION.md` - Software Bill of Materials

## Forbidden Directories

**Ignore when exploring** (performance + irrelevant content):

- `.venv/` - Python virtual environment
- `.git/` - Git metadata
- `__pycache__/` - Python bytecode
- `.pytest_cache/` - Test cache
- `models/` - Binary ML artifacts (.skops files)
- `node_modules/` - If present (not currently in project)

## Quick Troubleshooting

**Common issues**:

- `ModuleNotFoundError` → Activate venv: `source .venv/bin/activate` (macOS/Linux) or `.venv\Scripts\activate` (Windows)
- Pre-commit fails → Install hooks: `pre-commit install`, then retry commit
- Tests fail → Check Python version: `python --version` (must be 3.13+)
- Model loading fails → Verify .skops file exists: `ls -lh models/iris_classifier.skops`

**Detailed troubleshooting**: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) (comprehensive guide for common issues)

---

**Last Updated**: 2025-11-05 (Enhanced with index layer for progressive disclosure)
