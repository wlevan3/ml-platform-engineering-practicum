# Policy-as-Code

This directory groups the guardrail policies that continuously enforce platform
security and compliance requirements.

- `sentinel/` – HashiCorp Sentinel policies executed during Terraform Cloud/Enterprise
  or CI plan evaluations.
- `opa/` – Open Policy Agent (Rego) rules that Checkov, Conftest, or custom tooling use
  to validate Terraform plans.
- `checkov/` – Custom Checkov policies that extend the default IaC security scanners.

All policies are wired into the CI pipeline so that infrastructure changes failing
these rules never reach production. When adding a new guardrail, document the rationale
and link the enforcement in this README to keep reviewers oriented.
