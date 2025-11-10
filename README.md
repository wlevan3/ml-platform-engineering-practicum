<!-- markdownlint-disable MD013 -->
# ML Platform Engineering Practicum

> End-to-end ML platform implementation: EKS-based pipelines, model registry, CI/CD, feature store, and
> observability — with reflections on platform design.
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI Pipeline](https://github.com/wlevan3/ml-platform-engineering-practicum/actions/workflows/ci.yml/badge.svg)](https://github.com/wlevan3/ml-platform-engineering-practicum/actions/workflows/ci.yml)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=wlevan3_ml-platform-engineering-practicum&amp;metric=alert_status)](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=wlevan3_ml-platform-engineering-practicum&amp;metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=wlevan3_ml-platform-engineering-practicum&amp;metric=security_rating)](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
[![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=wlevan3_ml-platform-engineering-practicum&amp;metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)

## 🏆 Code Quality

This project maintains high code quality standards using **SonarCloud** and GitHub Actions:

- **Quality Gate**: Enforced on new code
- **Tooling**: `uv`, `ruff`, `mypy`, `pytest` as canonical
- **Philosophy**: "Clean as You Code" on top of a hardened baseline

See [`docs/SONARCLOUD_QUALITY_STANDARDS.md`](docs/SONARCLOUD_QUALITY_STANDARDS.md:1) for detailed metrics and thresholds.

## 📋 About

This repository documents a production-grade ML platform implementation, including:

- **Infrastructure as Code** — Terraform for AWS resources
- **Kubernetes on EKS** — GitOps-driven deployments
- **ML Infrastructure** — Model registry, feature store (planned), experiment tracking
- **CI/CD & Security** — Unified quality and security gates
- **Platform Engineering** — Opinionated patterns and hardening

[`STREAMLINING_PLAN.md`](STREAMLINING_PLAN.md:1) is the canonical specification for:

- The final repo layout (`src/`, `apps/`, `platform/`, `scripts/`, infra, and policy directories)
- Standardizing on `uv`, `ruff`, `mypy`, and `pytest` as the unified toolchain
- CI/CD and security workflows
- The ordered migration phases from legacy layouts to the converged architecture

All structural and tooling changes MUST follow [`STREAMLINING_PLAN.md`](STREAMLINING_PLAN.md:1).

## 🧱 Architecture Overview (Finalized)

The repository has converged on the Phase 8 target layout.

**Canonical components:**

- `src/ml_platform_api/` — Canonical Python library surface for API logic (schemas, security, model loading, training helpers, etc.)
- `apps/api/` — Canonical FastAPI application entrypoint facade
  - Runtime entrypoint: `apps/api/main.py`
  - Composes `src/ml_platform_api` without duplicating business logic
- `platform/scripts/` — Shared operational and infra-support scripts
- `scripts/` — Thin wrappers delegating to `platform/scripts` or app entrypoints
- `infra/` — Terraform modules, environments, and infra policies
- `clusters/` — Kubernetes cluster configuration and bootstrap manifests
- `argocd/` — Argo CD applications and projects for GitOps
- `policy/` — Sentinel/Rego and related policy-as-code
- `docs/` — Architecture, security, runbooks, and workflow documentation
- `.github/workflows/` — CI/CD, security, quality, and automation pipelines
- `tests/` — Central tests aligned with `src/` and `apps/`

**Compatibility shims:**

- `services/api/` — Legacy API layout preserved as a thin compatibility shim layer.
  - Imports from `src/ml_platform_api` and mirrors legacy module paths.
  - Must NOT be treated as the canonical implementation for new code.
  - Existing references (e.g., `uvicorn services.api.main:app`) remain supported until a future major version removes them.

## 🚀 Getting Started

### Prerequisites

- Python 3.11+
- Docker
- kubectl
- (Optional for infra) AWS Account, `terraform`, `aws-cli`, `helm`

### Environment Setup (Canonical: uv)

```bash
# Clone
git clone https://github.com/wlevan3/ml-platform-engineering-practicum.git
cd ml-platform-engineering-practicum

# Install uv (once, if not installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Sync environment from pyproject.toml + uv.lock
uv sync
```

`pyproject.toml` + `uv.lock` are the authoritative sources of Python dependencies.

If `requirements.txt` is used, it is compatibility-only and must be treated as generated from `uv` (do not edit manually).

### Running the API

Canonical FastAPI app (Phase 8 end state):

```bash
# Run via apps/api canonical entrypoint
uv run uvicorn apps.api.main:app --reload --host 0.0.0.0 --port 8000
```

Compatibility shim (supported for existing workflows):

```bash
# Legacy-style entrypoint using services/api shim (do not use for new integrations)
uv run uvicorn services.api.main:app --reload --host 0.0.0.0 --port 8000
```

In both cases, the underlying implementation is provided by `src/ml_platform_api`.

### Running Checks (Canonical)

These commands mirror the enforced CI behavior:

```bash
uv run ruff check .
uv run ruff format --check .
uv run mypy
uv run pytest
```

All new contributions MUST pass these gates.

## 🧭 Monorepo Layout

```text
src/
└── ml_platform_api/       # Canonical API/library package

apps/
└── api/                   # Canonical FastAPI entrypoint (apps/api/main.py)

services/
└── api/                   # Legacy compatibility shims only (imports from src/ml_platform_api)

platform/
└── scripts/               # Shared operational tooling

scripts/                   # Thin wrapper scripts only

infra/                     # Terraform, infra modules, infra policies
clusters/                  # Kubernetes manifests and cluster bootstrap
argocd/                    # Argo CD Applications and Projects
policy/                    # Central policy-as-code
docs/                      # Architecture, ops, security, workflows
.github/workflows/         # CI/CD and security workflows
tests/                     # Automated tests
```

Key rules:

- New shared Python code → `src/`
- New runtime services/entrypoints → `apps/`
- `services/api` is reserved for shims only; do not add new primary logic there.

## 📚 Documentation

Core references:

- [`CONTRIBUTING.md`](CONTRIBUTING.md:1) — Workflow, gates, and contribution rules
- [`docs/QUICK_REFERENCE.md`](docs/QUICK_REFERENCE.md:1) — Canonical commands and shortcuts
- [`SECURITY.md`](SECURITY.md:1) — Security posture and guardrails
- [`STREAMLINING_PLAN.md`](STREAMLINING_PLAN.md:1) — Authoritative technical spec

## 🛠️ Tooling Summary

- Dependencies: `uv` (`pyproject.toml` + `uv.lock`)
- Linting/Formatting: `ruff` (`ruff check`, `ruff format`)
- Typing: `mypy`
- Testing: `pytest`
- Pre-commit: Uses the same core tools; see [`.pre-commit-config.yaml`](.pre-commit-config.yaml:1)

`black` may appear only as a transitional/legacy reference; the canonical formatter is `ruff format`.

## 🤝 Contributing

Feedback and PRs are welcome. All contributions MUST:

- Use `uv` for environment and commands
- Pass `ruff`, `mypy`, and `pytest`
- Respect the `src/` + `apps/` + shim pattern documented above

See [`CONTRIBUTING.md`](CONTRIBUTING.md:1) for details.

## 📄 License

This project is licensed under the MIT License — see [`LICENSE`](LICENSE:1).
