# AWS Core Infrastructure

The `aws-core/` stack owns the foundational AWS resources required to run the ML platform:
networking, EKS control plane, container registry, IAM primitives, and supporting security
services. It is intentionally isolated from application configuration to keep blast radius
small and reviews focused.

Key entry points:

- `terraform/` – Primary Terraform root, modules, and operator docs (`terraform/README.md`).
- `terraform/environments/dev/` – Environment-specific state, variables, and wrapper scripts.
- `terraform/modules/` – Reusable Terraform modules shared across environments.

Bootstrap the remote backend and run Terraform from this directory:

```bash
./infra/aws-core/terraform/scripts/bootstrap-backend.sh   # one-time backend setup
cd infra/aws-core/terraform/environments/dev
terraform init
terraform apply
```

Additional environments (e.g., `staging`, `prod`) should be added alongside `dev/`, reusing
the same modules while keeping per-environment overrides explicit.
