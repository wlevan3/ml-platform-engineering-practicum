# Contributing to ML Platform Engineering Practicum

This document outlines the development workflow and contribution guidelines for this project.
While this is a personal learning project, contributions MUST follow production-grade practices
aligned with [`STREAMLINING_PLAN.md`](STREAMLINING_PLAN.md:1).

## Development Setup

### Python Environment (Canonical: uv)

All Python development MUST use `uv` with `pyproject.toml` + `uv.lock` as the single source of truth.

```bash
# From repo root
curl -LsSf https://astral.sh/uv/install.sh | sh  # if uv is not installed

# Sync environment
uv sync
```

Rules:

- Do NOT manually manage virtualenvs for canonical workflows.
- Do NOT edit `requirements.txt` directly; it is compatibility-only and may be regenerated from `uv`.
- Use `uv run ...` for all Python tooling and app commands documented below.

### Pre-Commit Hooks

This project uses **pre-commit hooks** for fast local feedback.

```bash
uv run pre-commit install
uv run pre-commit run --all-files
```

Key hooks include:

- Security: detect-secrets, detect-private-key, bandit, Checkov, Semgrep
- Code quality: `ruff` (lint + format), `mypy`
- Repo hygiene: trailing whitespace, EOF, YAML validation, etc.

`ruff`, `mypy`, and `pytest` in pre-commit MUST remain aligned with CI.

### What Gets Checked (Summary)

Security:

- `detect-secrets` — Hardcoded secrets
- `detect-private-key` — SSH/PGP keys
- `bandit` — Python security issues
- `checkov` — Terraform/Kubernetes/Dockerfile/secrets scanning
- Additional IaC and workflow checks as configured

Code & Config Quality:

- `ruff` — Python linting + formatting (canonical)
- `mypy` — Static typing
- `yamllint`, `actionlint`, markdown and Terraform tooling

General Hygiene:

- Trailing whitespace, EOF newlines
- Large file guardrails
- Merge conflict markers

### Handling Hook Failures

When a hook fails:

1. Read the output and understand the failure.
2. Fix the issue in your code or configuration.
3. Stage the changes.
4. Re-run `uv run pre-commit run` or retry the commit.

Do not bypass hooks (`--no-verify`) except in true emergencies with a documented reason.

## Canonical Tooling and Commands

These are non-optional gates for contributions and must match CI:

```bash
uv run ruff check .
uv run ruff format --check .
uv run mypy
uv run pytest
```

Guidance:

- `ruff` is the canonical linter and formatter (`ruff format` replaces Black).
- `mypy` is required for typing; new/updated code should type-check cleanly.
- `pytest` is the only supported test runner.

## Repository Layout and Where to Put Code

The layout is defined by [`STREAMLINING_PLAN.md`](STREAMLINING_PLAN.md:1). Key rules:

- `src/` — All reusable Python packages and shared logic.
  - New shared API/model/utilities go under `src/ml_platform_api/` or other `src/` packages.
- `apps/` — Runnable entrypoints that compose `src/`.
  - `apps/api/` is the canonical FastAPI service.
  - `apps/api/main.py` is the canonical API runtime entrypoint facade.
- `services/api/` — Legacy compatibility shims ONLY.
  - Shims import from `src/ml_platform_api`.
  - Do NOT add new primary business logic here.
  - Existing external references (e.g. `services.api.main:app`) remain supported until an intentional major change.
- `platform/scripts/` — Shared operational scripts (infra, cleanup, verification).
- `scripts/` — Thin wrappers that delegate to `platform/scripts` or app entrypoints.
- `infra/`, `clusters/`, `argocd/`, `policy/`, `.github/workflows/` — Infra, GitOps, policy, and workflow definitions.
- `tests/` — Tests aligned with `src/` and `apps/` (and any shims that must remain compatible).

### Adding or Modifying Python Code

- New shared functionality:
  - Implement in `src/<package>/...`.
  - Add/extend tests in `tests/` (or aligned app-local tests).
- New service or entrypoint:
  - Add in `apps/<name>/`.
  - Wire it via `apps/<name>/main.py` and import from `src/`.
- Legacy `services/api`:
  - Only update to maintain compatibility with `src/ml_platform_api` and `apps/api`.
  - Do not treat it as the primary source of truth.

## CI Alignment

All changes MUST be compatible with CI:

- `ci.yml` runs (authoritatively, via `uv`):
  - `uv sync`
  - `uv run ruff check .`
  - `uv run ruff format --check .`
  - `uv run mypy`
  - `uv run pytest`
- Security workflows (`security-gate`, `codeql`, `scorecard`, etc.) enforce additional gates.

Before opening a PR:

```bash
uv run ruff check .
uv run ruff format --check .
uv run mypy
uv run pytest
```

These commands MUST pass locally.

## Code Quality and Security Expectations

- Follow `ruff` style and fix violations instead of adding broad ignores.
- Maintain or improve type coverage; avoid introducing untyped, dynamic patterns.
- Ensure tests are deterministic and CI-friendly.
- Never commit secrets; update `.secrets.baseline` only with justification.
- Respect existing security policies described in:
  - [`SECURITY.md`](SECURITY.md:1)
  - [`docs/SECURITY.md`](docs/SECURITY.md:1)
  - Related IaC/security docs under `docs/` and `infra/`.

## Development Workflow (Summary)

1. Create an issue or task.
2. Branch from `main`.
3. Implement changes in the correct location:
   - `src/` for shared libs
   - `apps/` for entrypoints
   - `services/api` only for shims/compat
4. Run canonical checks:

   ```bash
   uv run ruff check .
   uv run ruff format --check .
   uv run mypy
   uv run pytest
   uv run pre-commit run --all-files
   ```

5. Open a PR; ensure CI (including `ci.yml` and security workflows) passes.

All contributions MUST align with [`STREAMLINING_PLAN.md`](STREAMLINING_PLAN.md:1) and the Phase 8 end state described there.
