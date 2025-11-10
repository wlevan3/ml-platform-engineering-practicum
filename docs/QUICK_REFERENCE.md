# Quick Reference Guide

Quick commands and workflows for the ML Platform Engineering Practicum.

## Git Workflow

```bash
# Create feature branch from main
git checkout main
git pull origin main
git checkout -b feature/your-feature-name

# Make changes...

# Commit with conventional commits
git add .
git commit -m "feat(component): add feature description"

# Push and create PR
git push -u origin feature/your-feature-name
gh pr create --title "feat: Feature title" --body "Description" --web
```

## Python Development (Canonical)

### Environment Setup

```bash
# From repo root

# Install uv if needed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Sync environment from pyproject.toml + uv.lock
uv sync
```

- `pyproject.toml` + `uv.lock` are authoritative.
- `requirements.txt` is compatibility-only (generated from `uv`) and MUST NOT be edited manually.

### API Server

Canonical entrypoint (Phase 8):

```bash
# Run FastAPI app via canonical apps/api facade
uv run uvicorn apps.api.main:app --reload --host 0.0.0.0 --port 8000
```

Compatibility shim (supported, non-canonical):

```bash
# Legacy path using services/api (shim backed by src/ml_platform_api)
uv run uvicorn services.api.main:app --reload --host 0.0.0.0 --port 8000
```

### Model Training

```bash
# Train and save model artifacts via canonical training module
uv run python -m ml_platform_api.train_model
```

(If legacy `train_model.py` exists, it MUST behave as a thin wrapper around `src/ml_platform_api`.)

### Testing

Canonical:

```bash
uv run pytest
```

Examples:

```bash
# With verbose output
uv run pytest -v

# Run a specific test file
uv run pytest tests/test_ml_platform_and_ci_alignment.py
```

### Code Quality (Canonical)

```bash
# Lint
uv run ruff check .

# Format check (CI-aligned)
uv run ruff format --check .

# Apply formatting locally
uv run ruff format .

# Type checking
uv run mypy

# Run all pre-commit hooks (uses Ruff + mypy + security/IaC hooks)
uv run pre-commit run --all-files
```

Ruff is the primary formatter and linter. Black is not part of the canonical toolchain.

## Docker

```bash
# Build image
docker build -t ml-platform-api:latest .

# Run container
docker run -p 8000:8000 ml-platform-api:latest

# Test health and predict endpoints (assuming default port)
curl http://localhost:8000/health/ready
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"features": [5.1, 3.5, 1.4, 0.2]}'
```

## Cleanup / Teardown (Canonical)

Status: Canonical operational guidance is defined in [`docs/CLEANUP_RUNBOOK.md`](docs/CLEANUP_RUNBOOK.md:1).

For any teardown or cleanup activity:

- Follow the runbook.
- Use these canonical entrypoints only:

```bash
# Layer A: Standard Terraform-based destroy (recommended)
cd infra/aws-core/terraform/environments/dev
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan

# Layer B: Manual verification helpers (from repo root)
./scripts/validate-terraform-state.sh
./scripts/validate-resource-tags.sh
./scripts/verify-aws-resources-deleted.sh

# Layer C: Nuclear / emergency tools (manual only, see runbook for warnings)
platform/scripts/aws-resource-inventory.sh
platform/scripts/aws-nuclear-cleanup.sh
platform/scripts/verify-cleanup.sh
```

## Kubernetes Workflow

```bash
# Validate manifests
kubectl apply --dry-run=client -f clusters/dev/bootstrap/k8s-manifests/

# Apply manifests
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/

# Check status
kubectl get pods
kubectl get services

# View logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>
```

## ArgoCD Workflow

```bash
# Apply ArgoCD Projects
kubectl apply -f argocd/projects/

# Apply ArgoCD Applications
kubectl apply -f argocd/applications/

# Check Sync Status
argocd app get ml-platform-api
argocd app get ml-platform-resource-quotas
```

## Layout Summary (End-State Reference)

- `src/ml_platform_api` — Canonical library for API/model logic.
- `apps/api` — Canonical FastAPI entrypoint (`apps/api/main.py`).
- `services/api` — Legacy compatibility shims only; backed by `src/ml_platform_api`.
- `platform/scripts` — Shared operational tooling (Terraform, cleanup, validation).
- `scripts/` — Thin wrappers delegating to `platform/scripts` or `apps/`.
- `infra/`, `clusters/`, `argocd/`, `policy/`, `.github/workflows/` — Infra, GitOps, policy, CI/CD, security.
- `tests/` — Tests aligned with `src/` and `apps/`.

For authoritative details, see [`STREAMLINING_PLAN.md`](STREAMLINING_PLAN.md:1).
