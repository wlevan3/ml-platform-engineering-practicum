# Infrastructure Layer

The `infra/` directory contains everything required to provision and govern
the cloud foundation for the ML platform.

- `aws-core/` – Terraform roots and reusable modules that stand up shared AWS services
  (VPC, EKS, ECR, networking, security monitoring, etc.). See
  `infra/aws-core/terraform/README.md` for module documentation and operator runbooks.
- `policies/` – Policy-as-code guardrails that run in CI/CD or during manual plan review.
  Sentinel, OPA/Rego, and Checkov custom checks live here so they can evolve alongside
  the infrastructure they protect.

Future infrastructure stacks (for example, data-platform or analytics workspaces) should
be added as additional subdirectories within `infra/`, keeping a clear separation between
foundational cloud resources and higher-level platform services.
