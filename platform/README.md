# Platform Tooling

Shared automation, developer tooling, and operational scripts live in `platform/`.
Anything that multiple services or infrastructure stacks rely on should be centralized
here to avoid duplication.

- `scripts/` – Bash and Python helpers used for environment bootstrap, local cluster
  deployment, Terraform safeguards, and diagnostics.

When adding a new script, document its usage in the script header and, if applicable,
reference it from the relevant README (e.g., infrastructure, clusters, or services).
This keeps runbooks accurate and helps new contributors discover existing automation.
