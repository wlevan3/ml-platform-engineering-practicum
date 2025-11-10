# Cleanup Prevention Strategy – Orphaned Resource Detection
Status: Reference context for cleanup; canonical operational guidance is in docs/CLEANUP_RUNBOOK.md.

This document explains how our CI/CD pipelines guard against orphaned AWS resources after Terraform destroy operations.

## Goals

1. Run controlled destroy validation before production merges.
2. Verify that the AWS resource graph matches Terraform state.
3. Alert on any lingering NAT gateways, VPC endpoints, EIPs, or security groups.

## Approach

We combine several automated checks:

- The `terraform-destroy-validation.yml` workflow executes a temporary cluster destroy followed by API validation of the tagged resources.
- The `nightly-resource-audit.yml` workflow monitors the `ml-platform-dev` cluster and files issues when `ResourceGroupsTaggingAPI` detects lingering resources.
- Utility scripts such as `scripts/verify-aws-resources-deleted.sh` and `infra/aws-core/terraform/environments/dev/nat-polling-functions.sh` provide reusable polling and verification logic.

## References

- [Emergency cleanup bugs and their symptoms](EMERGENCY_CLEANUP_BUGS.md)
- [Terraform destroy testing matrix](TERRAFORM_DESTROY_TESTING_STRATEGY.md)
- [Resource tagging standards](CLEANUP_PREVENTION_CHECKLIST.md)

## Next steps

1. Run the nightly audit workflow to confirm no orphaned resources remain after destroy tests.
2. Update the reference list above if we add new validation scripts or workflows.
3. Keep Terraform modules and scripts aligned with the strategy described here.
