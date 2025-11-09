# Emergency cleanup script bugs

This document summarizes the critical failure modes we observed while running the emergency cleanup script (`infra/aws-core/terraform/environments/dev/emergency-cleanup-improved.sh`).

## Key findings

1. **VPC endpoints are not deleted**, which causes Terraform to fail with conflicting DNS entries when `private_dns_enabled = true`.
2. **Elastic IPs remain associated** while NAT gateways are still deleting, leading to `Resource.AlreadyAssociated` errors.
3. **Region-wide filters risk deleting unrelated resources** because the cleanup script operates on all tagged VPCs without cluster scoping.
4. **EC2 instances survive cleanup**, which increases cost and leads to stale nodes.

## Remediation actions

- Always delete VPC endpoints before removing NAT gateways, and verify that the corresponding ENIs are gone.
- Poll NAT gateway and EIP status with exponential backoff before attempting to release each Elastic IP.
- Apply strict tag filters (cluster name + managed-by) to every AWS CLI call the script makes.
- Validate that no EC2 instances remain after the scripted destroy completes.

## References

- [NAT gateway polling helper](../infra/aws-core/terraform/environments/dev/nat-polling-functions.sh)
- [Nightly resource audit](../.github/workflows/nightly-resource-audit.yml)
- [Terraform destroy validation workflow](../.github/workflows/terraform-destroy-validation.yml)
