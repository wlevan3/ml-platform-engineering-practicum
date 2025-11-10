# STREAMLINING_PLAN.md — Authoritative Implementation Spec

This document is the single source of truth for:

- Repository architecture and directory layout.
- Python environment and dependency management.
- Code quality, typing, security, and CI/CD enforcement.
- Contributor workflows.
- The ordered, verifiable migration path from the current state to the target architecture.

All instructions are concrete and implementable. Any prior conflicting or purely aspirational guidance is superseded by this specification.

---

## 1. Monorepo Architecture (Target End State)

### 1.1 Objectives

- Enable secure, reproducible ML experimentation and productionization.
- Provide a clear contributor experience with one obvious workflow to:
  - Set up the environment.
  - Run checks locally.
  - Understand, extend, and operate the platform.
- Make security, typing, testing, and automation non-optional and enforced via CI/CD.
- Avoid ad-hoc structures and divergence from a well-defined monorepo layout.

### 1.2 Target Top-level Layout

Final converged structure:

- `src/`
  - All reusable Python packages and libraries.
  - Shared logic for:
    - Data loading and validation.
    - Feature engineering.
    - Model training and evaluation.
    - Utilities (logging, config, security helpers).
  - Structured as installable packages (e.g. `src/ml_platform/`, `src/ml_platform_api/`).
- `apps/`
  - Runnable entrypoints that compose `src/`:
    - `apps/api/` — FastAPI inference service (canonical).
    - `apps/batch/` — Optional batch or scheduled jobs.
    - `apps/cli/` — Optional CLI tools.
  - Each app:
    - Depends on `src/` packages.
    - Contains only thin wiring, configuration, and adapters.
- `infra/`
  - Infrastructure-as-code:
    - Terraform modules and environments (e.g. `infra/aws-core/terraform/...`).
    - Shared infra policies and helper scripts (e.g. `infra/policies/`).
- `clusters/`
  - Kubernetes cluster configuration and bootstrap manifests.
  - Environment-specific overlays and namespaces.
- `argocd/`
  - Argo CD Applications and Projects for GitOps-based deployments.
- `.github/workflows/`
  - All CI/CD and automation workflows (see Section 5).
- `docs/`
  - Markdown documentation:
    - Architecture.
    - Security.
    - Operations and runbooks.
    - Contribution and style guides.
    - Tooling and workflow documentation.
- `tests/`
  - Top-level tests mirroring `src/` and `apps/` for cross-cutting coverage.
  - May coexist with app-local `tests/` where clearer; all use the same tooling and CI.
- `platform/`
  - Shared operational scripts tightly related to infra/platform management:
    - Terraform/policy helpers.
    - Cleanup, verification, and validation scripts.
  - No application business logic or ML model logic.
- `scripts/`
  - Thin wrappers only.
  - Each delegates directly to the corresponding `platform/` script or `apps/` entrypoint.
- `policy/`
  - Policy-as-code (e.g. Sentinel, Rego) shared across infra.
- Project metadata/config:
  - `.pre-commit-config.yaml`, `.ruff.toml` or `pyproject.toml`-embedded config, `mypy.ini`, `pytest.ini`,
    `.checkov.yaml`, `.trivy.yaml`, `.kube-linter.yaml`, `.tflint.hcl`, `.tfsecignore`, `.github/SECRETS.md`,
    markdownlint configs, and similar authoritative configuration.

No new top-level directory patterns are allowed without updating this specification.

### 1.3 Current State Alignment

- Current repo includes (non-exhaustive):
  - `services/api/` FastAPI service.
  - `infra/aws-core/terraform/...`, `infra/policies/`, `platform/scripts`, `policy/terraform`, `.github/workflows/ci.yml`, `.github/workflows/codeql.yml`, `.github/workflows/scorecard.yml`, and various security configs.
  - `requirements.txt`, `mypy.ini`, `.pre-commit-config.yaml`, markdownlint configs, etc.
- Target mapping:
  - `services/api` is logically converging into:
    - `apps/api/` for the FastAPI entrypoint.
    - `src/ml_platform_api/` (or equivalent) for shared API/library logic.
- Migration will:
  - Introduce `src/` and `apps/`.
  - Gradually refactor `services/api` into that layout without breaking CI.
- Any layout deviation MUST be justified in this spec before implementation.

---

## 2. Python Environment and Dependencies

### 2.1 Toolchain (Non-negotiable Direction)

- Primary language: Python 3.13 (or the highest stable version supported by `uv` and CI runners; pinned explicitly).
- Dependency and environment management: `uv` (authoritative).
- Packaging metadata:
  - Managed via `pyproject.toml` at the repo root.
  - `uv.lock` committed as the source of truth for resolution.

Any previous use of pip-tools, Pipenv, or multiple parallel strategies is superseded by this `uv`-centric model.

### 2.2 Dependency Model

- `pyproject.toml`:
  - Defines:
    - Project metadata.
    - Core dependencies for libraries under `src/`.
    - Optional dependency groups (examples):
      - `[dependency-groups.dev]` — testing, linting, typing, tooling.
      - `[dependency-groups.apps]` — FastAPI, uvicorn, etc.
      - Additional groups for security/infra tooling if needed.
- `uv.lock`:
  - Always present and committed.
  - Generated and updated exclusively via `uv`.
- `requirements.txt`:
  - Optional and compatibility-only.
  - If present:
    - Generated from `uv` (e.g. via `uv export`).
    - Clearly labeled as derived and non-authoritative.
    - Not manually edited.

### 2.3 Environment Usage

- Local development:
  - `uv sync` to create and populate the environment from `pyproject.toml` + `uv.lock`.
  - `uv run` to execute commands (e.g. `uv run ruff check .`, `uv run mypy`, `uv run pytest`).
- CI:
  - Use `uv` for dependency installation with caching keyed on `uv.lock`.
  - Do not use `pip install -r requirements.txt` in CI, except:
    - In explicitly documented compatibility jobs that do not define the canonical behavior.

---

## 3. Code Quality, Style, and Typing

### 3.1 Ruff as Unified Linter and Primary Formatter

- Ruff is the primary tool for:
  - Linting: `ruff check`.
  - Formatting: `ruff format`.
- Configuration:
  - `.ruff.toml` at repo root (or equivalent in `pyproject.toml`).
  - Baseline:
    - Core error/warning sets (`E`, `F`, etc.).
    - Import sorting.
    - Relevant code-quality and security rules for Python/ML.
  - Ignore rules:
    - Minimal, documented, and justified.

Black:

- If present in `.pre-commit-config.yaml`, it is transitional and secondary.
- Target state: Ruff-only formatting, enforced consistently.
- Migration steps define when Black can be safely removed.

### 3.2 Mypy for Static Typing

- Mypy is mandatory.

Policy:

- All new Python code:
  - Must be type-annotated (at least function signatures).
  - Must pass mypy under the repo configuration.
- Existing code:
  - Gradually migrated toward stronger typing.
  - May adopt per-module/package strictness as part of the migration.

`mypy.ini`:

- Targets the chosen Python version (aligned with Section 2.1).
- Includes:
  - `src/` packages.
  - Key `apps/` modules.
- Explicitly documents any exclusions with rationale and a plan (or acceptance) for resolution.

### 3.3 Testing with pytest

- pytest is the sole test runner.

Requirements:

- Tests are deterministic, hermetic where possible, and CI-friendly.
- Unit tests:
  - For core utilities, domain logic, and model interfaces in `src/`.
- Integration tests:
  - For end-to-end flows (e.g. `apps/api` endpoints).
- `pytest.ini`:
  - Defines:
    - Test paths (`tests/` and any app-local `tests/`).
    - Markers.
    - Coverage configuration when required by CI.

---

## 4. Security, Compliance, and Guardrails

### 4.1 Baseline Controls

- Dependencies:
  - Pinned via `uv.lock`.
  - Regularly scanned.
- Secrets:
  - Never committed.
  - Enforced via:
    - `.gitignore`.
    - Secret-scanning in CI.
    - `.github/SECRETS.md` policies.
- Static analysis:
  - CodeQL as primary SAST for Python (and other supported languages, if applicable).
- Vulnerability scanning:
  - Dependency and image scanning via Trivy (or equivalent).
- Infrastructure-as-Code:
  - Terraform:
    - Checkov, tfsec, TFLint using repo configs.
  - Kubernetes:
    - kube-linter or equivalent where manifests exist.

### 4.2 Quality/Security Gate

A PR to `main` MUST fail if:

- `ruff check` fails.
- Mypy type-checking fails (for enforced scopes).
- pytest tests fail.
- Configured high/critical security checks fail without an approved, documented exception.

Exceptions:

- Implemented via:
  - Explicit ignore/allowlist files (e.g. `tfsecignore`, `trivyignore`).
  - Documented rationale in code, config, or `SECURITY.md`.
- Ad-hoc, undocumented exceptions are not permitted.

---

## 5. CI/CD Workflows (Target End State)

All workflows live in `.github/workflows/`. Legacy or redundant workflows are updated or removed via the migration steps.

### 5.1 `ci.yml` — Core Quality Pipeline

Triggers:

- `pull_request` targeting `main`.
- `push` to `main`.

Authoritative behavior (adapted to repo needs):

- Checkout.
- Set up the agreed Python version.
- Install `uv`.
- Cache based on OS, Python version, and `uv.lock` hash.
- Run:
  - `uv sync`.
  - `uv run ruff check .`.
  - `uv run ruff format --check .` (once Ruff formatting is canonical).
  - `uv run mypy`.
  - `uv run pytest`.
- Optionally:
  - Upload coverage reports as artifacts.
  - Run lightweight IaC formatting/validation (non-destructive).

`ci.yml` is a required check for merges to `main`.

### 5.2 `security-gate.yml` — Security and Vulnerability Enforcement

Triggers:

- Scheduled (e.g. daily).
- `workflow_dispatch`.
- Optional: specific labels or paths.

Behavior:

- Runs:
  - Dependency scanning (e.g. Trivy or equivalent).
  - IaC scanning (Checkov/tfsec/TFLint) with stricter thresholds than `ci.yml`.
- Fails when:
  - High/critical vulnerabilities exist without an approved exception.

`security-gate.yml` becomes a required check for `main` once stable.

### 5.3 `codeql.yml` — CodeQL SAST

Triggers:

- `push` to `main`.
- `pull_request` to `main`.
- Scheduled.

Behavior:

- Standard GitHub CodeQL workflow (Python and any other relevant ecosystems).
- Uploads results to GitHub code scanning.
- Required check for `main`.

### 5.4 `scorecard.yml` — Supply Chain and Repo Hygiene

- Remains enabled to maintain OpenSSF Scorecard or equivalent.
- Treated as part of security posture.

### 5.5 `docs.yml` (Optional)

- Introduced only if/when docs build/validation becomes non-trivial.
- Runs linting/build checks for docs as needed.

### 5.6 Branch Protection

Branch protection for `main` MUST:

- Require:
  - Passing `ci.yml`.
  - Passing `codeql.yml`.
  - Passing `security-gate.yml` (once present and stable).
  - Other critical security workflows as designated.
- Disallow direct pushes to `main`.
- Require PR reviews per org policy.

---

## 6. Contributor and Maintainer Experience

### 6.1 Getting Started

From repo root:

```bash
# Install uv (once, if not installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Sync environment
uv sync

# Run all checks before opening a PR
uv run ruff check .
uv run ruff format --check .
uv run mypy
uv run pytest
```

These commands MUST mirror CI behavior.

### 6.2 Adding or Modifying Code

- New reusable logic:
  - Add under `src/` (e.g. `src/ml_platform/...`).
  - Add/update tests under `tests/` or app-local `tests/`.
- New app/entrypoint:
  - Add under `apps/<name>/`.
  - Import only from `src/`, standard library, and approved dependencies.
  - Include tests.
- Dependencies:
  - Update `pyproject.toml`.
  - Run `uv sync` to update `uv.lock`.
  - Commit both files.

### 6.3 Interacting with CI

- On PR:
  - `ci.yml` and security workflows run automatically.
- To fix failures:
  - Ruff: `uv run ruff check .` / `uv run ruff format .`.
  - Mypy: `uv run mypy`.
  - Tests: `uv run pytest`.

Local and CI workflows MUST use the same core tools and commands to avoid divergence.

---

## 7. Non-negotiable Standards and Guardrails

1. Dependencies:
   - Pinned via `uv.lock`.
   - No unmanaged or side-loaded runtime dependencies.
2. Typing:
   - New code typed; existing code converges toward typed according to this plan.
3. Tooling:
   - `uv`, `ruff`, `mypy`, `pytest` are mandatory.
4. Scripts:
   - No new arbitrary script roots.
   - Shared scripts live in `platform/scripts`.
   - Root `scripts/` contains only thin wrappers.
   - Infra-local scripts may live next to their Terraform modules when specific to that context.
5. Secrets:
   - Never stored in code or versioned configs.
6. ML-specific:
   - Training/eval code reproducible, config-driven, and reviewable.
   - Notebooks (if present) live under `docs/` or `notebooks/` and are never production runtime code.

---

## 8. Decommissioning Legacy and Conflicting Instructions

This plan supersedes any guidance promoting:

- Multiple dependency managers as peers.
- `requirements.txt` as manually authoritative.
- Multiple formatter stacks without a clear primary tool.
- Weak, vague, or optional CI/quality gates.

Conflicting docs, workflows, or configs MUST be updated or removed as part of the migration steps in Section 9.

---

## 9. Migration Steps (Authoritative, Scoped to This Repo)

This section defines ordered, incremental actions to align the repository with this spec while keeping CI green. Each step should be implemented via focused PRs with clear verification.

Each step includes:

- Actions (files/dirs/workflows).
- Configuration changes.
- Verification commands.
- Dependencies on previous steps where relevant.

### Step 1: Align Documentation with Target Architecture (Non-breaking)

Actions:

1. Update [`README.md`](README.md):
   - Document the current layout:
     - `services/api` as the existing FastAPI example.
     - `infra/`, `clusters/`, `argocd/`, `platform/`, `policy/`, `docs/`, `.github/`.
   - Add a concise “Architecture Roadmap”:
     - State the migration direction:
       - `src/` for libraries.
       - `apps/` for services.
     - Reference this [`STREAMLINING_PLAN.md`](STREAMLINING_PLAN.md) as authoritative.

2. Update `.github/workflows/README.md` (if present):
   - List currently active workflows:
     - `ci.yml` (core checks).
     - `codeql.yml`.
     - `scorecard.yml`.
   - Mention planned `security-gate.yml` per this plan.

Verification:

- `markdownlint` passes.
- Links to [`STREAMLINING_PLAN.md`](STREAMLINING_PLAN.md) and workflows resolve.

### Step 2: Introduce pyproject.toml and uv.lock (Non-breaking)

Actions:

1. Create `pyproject.toml` at repo root with at least:
   - `[project]` metadata (name, version, description).
   - `requires-python` set to the chosen baseline (e.g. `">=3.11"` or higher), matching reality and CI.
   - Dependencies aligned with existing `requirements.txt`.
   - `[dependency-groups.dev]` including:
     - `ruff`, `mypy`, `pytest`, and tools from `.pre-commit-config.yaml`.

2. Run:
   - `uv lock` (or `uv sync`) to generate `uv.lock`.

3. Update `.gitignore`:
   - Ensure `uv.lock` is NOT ignored.

4. Keep `requirements.txt` temporarily:
   - Add a header comment:
     - “Generated for compatibility; `pyproject.toml` + `uv.lock` (via `uv`) are authoritative.”

Verification:

- `uv sync` succeeds locally.
- `uv run pytest` (or existing tests) succeed.
- Existing `ci.yml` continues to pass (can still use its existing install method in this step).

### Step 3: Standardize Linting and Formatting (Ruff-first)

Actions:

1. Add or update `.ruff.toml` to configure:
   - Target Python version (aligned with Step 2).
   - Enabled rulesets and exclusions (minimal, documented).

2. Update `.pre-commit-config.yaml`:
   - Ensure a modern `ruff` hook is present.
   - If `black` remains:
     - Clearly mark Ruff formatting as the long-term default.
     - Avoid conflicting style requirements.

3. Update `CONTRIBUTING.md`:
   - Document:
     - `uv run ruff check .`
     - `uv run ruff format .` (when adopted).
     - `uv run mypy`
     - `uv run pytest`

Verification:

- `uv run ruff check .`
- `uv run mypy`
- `uv run pytest`
- `pre-commit run --all-files`
- All pass or have only explicitly documented transitional exceptions.

Incremental:

- Initial PR updates configs and docs.
- Later PRs may remove `black` once Ruff formatting is enforced repo-wide.

### Step 4: Update ci.yml to Use uv and Enforce Core Gates

Actions:

1. Edit `.github/workflows/ci.yml` to:
   - Use the agreed Python version.
   - Install `uv`.
   - Cache based on `uv.lock`.
   - Run:
     - `uv sync`
     - `uv run ruff check .`
     - `uv run mypy`
     - `uv run pytest`
   - Retain compatible existing checks:
     - YAML/actionlint, Dockerfile lint, basic IaC checks, etc.

2. Ensure job names and steps are stable and descriptive.

Verification:

- On PRs:
  - `ci.yml` passes end-to-end using `uv`.
- Locally:
  - `uv sync`
  - `uv run pytest`
  - Both succeed.

Incremental:

- Perform in a dedicated PR.
- Confirm no critical jobs rely on unmanaged `pip` unless explicitly documented.

### Step 5: Introduce security-gate.yml and Align CodeQL

Actions:

1. Add `.github/workflows/security-gate.yml`:
   - Triggers:
     - Scheduled (e.g. nightly).
     - `workflow_dispatch`.
   - Jobs:
     - Run Trivy (or chosen scanner) on dependencies/images.
     - Run Checkov/tfsec/TFLint on Terraform.
   - Fail on:
     - High/critical findings in scope, respecting configured ignore lists.

2. Review and adjust `.github/workflows/codeql.yml`:
   - Ensure triggers:
     - `push` to `main`, `pull_request` to `main`, and scheduled.
   - Ensure Python (and other applicable languages) are analyzed.

3. Update `.github/workflows/README.md`:
   - Document:
     - `security-gate.yml` purpose and thresholds.
     - Exception process.

Verification:

- `security-gate.yml` succeeds on current `main`.
- `codeql.yml` runs and reports to code scanning.

Incremental:

- Add `security-gate.yml` in one PR.
- Make it a required check in branch protections once stable.

### Step 6: Normalize Scripts and Platform Tooling

Actions:

1. Inventory:
   - `platform/scripts/`
   - `scripts/`
   - Scripts under `infra/` and related directories.

2. Apply rules:
   - Shared, reusable scripts:
     - Centralize or confirm under `platform/scripts/`.
   - Root `scripts/`:
     - Convert to thin wrappers calling `platform/scripts/...` or `uv run ...`.
   - Infra-local scripts:
     - Remain co-located when tightly bound to a specific Terraform/environment.

3. Update references in:
   - [`README.md`](README.md)
   - `docs/*`
   - `.github/workflows/*.yml`
   - To point to canonical script locations.

Verification:

- All referenced scripts exist and run.
- CI jobs using scripts pass.

Incremental:

- Start with scripts referenced by CI; then clean up others.

### Step 7: Introduce src/ and apps/ and Migrate services/api Incrementally

Actions:

1. Create:
   - `src/ml_platform_api/` (or similar) for API shared logic.
   - `apps/api/` for the FastAPI entrypoint.

2. Refactor (incrementally, non-breaking):
   - Move pure logic from `services/api` into `src/ml_platform_api/`:
     - Schemas, model logic, security helpers, utilities.
   - Implement `apps/api/main.py` that:
     - Imports from `src/ml_platform_api`.
     - Preserves behavior equivalent to current `services/api/main.py`.

3. Maintain compatibility during migration:
   - Option A:
     - Keep `services/api` as a thin wrapper delegating to `apps/api` / `src/ml_platform_api`.
   - Option B:
     - Update Dockerfile, docs, and CI to `apps/api`, then remove `services/api` once verified.

4. Update:
   - Dockerfile CMD to:
     - `uvicorn apps.api.main:app --host 0.0.0.0 --port 8000`
   - Tests:
     - Update imports to target `src/` and `apps/` paths.

Verification:

- `uv run pytest` passes.
- `uv run ruff check .` and `uv run mypy` pass for migrated modules.
- Manual/local:
  - `uv run uvicorn apps.api.main:app --reload` serves API successfully.

Incremental:

- PR 1:
  - Introduce `src/` + `apps/` and initial wiring.
- PR 2:
  - Migrate tests and references.
- PR 3:
  - Remove/reduce `services/api` once unused.

### Step 8: Tighten Type Checking, Linting, and Test Coverage

Actions:

1. Update `mypy.ini`:
   - Include new `src/` and `apps/` packages.
   - Increase strictness incrementally on critical modules.

2. Update `.ruff.toml`:
   - Ensure all relevant directories are included.

3. Confirm `pytest.ini`:
   - Discovers `tests/` and app-local tests.

Verification:

- `uv run mypy` succeeds or has only explicitly tracked TODOs.
- `uv run ruff check .` succeeds.
- `uv run pytest` succeeds.

Incremental:

- Enforce strictness module-by-module.
- Fail CI on regressions in covered scopes.

### Step 9: Finalize Gates and Clean Up Legacy Artifacts

Actions:

1. Branch protection:
   - Require:
     - `ci.yml`
     - `codeql.yml`
     - `security-gate.yml` (once stable)
     - Other critical workflows as declared.

2. Remove or update:
   - Obsolete workflows not aligned with this plan.
   - Docs referencing:
     - `services/api` as canonical once `apps/api` is primary.
     - `requirements.txt` as authoritative once `pyproject.toml` + `uv.lock` are stable.
     - Deprecated/orphaned tooling.

3. Align meta-instruction files:
   - `.cursorrules`, `AGENTS.md`, `CLAUDE.md`, and similar:
     - MUST reflect:
       - `uv` + `pyproject.toml` + `uv.lock`
       - Ruff, Mypy, Pytest
       - The new layout and CI rules.
     - MUST NOT contradict this spec.

Verification:

- All required workflows pass on `main`.
- No broken references to removed paths.
- Documentation matches actual layout and toolchain.

Incremental:

- Execute as final cleanup PRs after prior steps are stable.

---

## 10. End State Summary

When all migration steps are complete:

- Layout:
  - `src/` for reusable libraries.
  - `apps/` for services and entrypoints (API, batch, CLI).
  - `infra/`, `clusters/`, `argocd/`, `platform/`, `policy/`, `docs/`, `tests/`, `.github/`, `scripts/` (wrappers).
- Tooling:
  - `uv` + `pyproject.toml` + `uv.lock` as the single source for dependencies and environments.
  - `ruff` as unified linter and formatter (once finalized).
  - `mypy` for typing.
  - `pytest` for tests.
- CI/CD:
  - `ci.yml` enforcing lint, type-check, and tests via `uv`.
  - `codeql.yml` for SAST.
  - `security-gate.yml` for dependency/IaC/image scanning with defined thresholds.
  - `scorecard.yml` for supply chain health.
- Gates:
  - Merges to `main` require all core CI and security jobs to pass.
  - Exceptions are explicit, documented, and rare.
- Contributor experience:
  - Local workflows match CI.
  - The path to adding services, libraries, infra, and docs is clear, documented, and consistent with this specification.

This specification, including the migration steps, is authoritative for all future changes to this repository’s architecture, tooling, workflows, and quality/security posture.
