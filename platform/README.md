# Platform Tooling

Shared automation, developer tooling, and operational scripts live in `platform/`.
Anything that multiple services or infrastructure stacks rely on should be centralized
here to avoid duplication.

- `platform/scripts/` – Canonical shared helpers used for environment bootstrap,
  local cluster workflows, Terraform safeguards, cleanup, and diagnostics.
- `scripts/` – Thin wrapper entrypoints that delegate into `platform/scripts/`
  (or, in future, application entrypoints). No substantial logic should live here.

When adding a new script under `platform/scripts/`, document its usage in the script
header and, if applicable, reference it from the relevant README (e.g., infrastructure,
clusters, or services). Keep `./scripts/*.sh` as minimal delegating shims only.
