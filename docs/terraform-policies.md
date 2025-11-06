# Terraform Policy Guardrails

## Customer-Managed KMS Keys

- Checkov policy: `checkov_policies/CKV_CUSTOM_AWS_001.yaml`
- OPA policy: `infra/policies/opa/kms.rego`
- Sentinel policy: `infra/policies/sentinel/kms.sentinel`
- Sentinel mock config: `infra/policies/sentinel/dev.hcl`
- Runtime hook: all three policies run during the `terraform-validate` job in `.github/workflows/ci.yml`
- Plan helper: `platform/scripts/assert-no-cmk.sh` fails when a plan introduces `aws_kms_key` resources

### What it does

Every guardrail denies Terraform plans that introduce `aws_kms_key` resources (except when the change list is a pure delete). This enforces the platform decision to rely exclusively on AWS-managed encryption.

### Run it locally

```bash
cd infra/aws-core/terraform/environments/dev
terraform plan -out plan.tfplan -no-color
terraform show -json plan.tfplan > plan.json
cd ../../..
python3 platform/scripts/generate_sentinel_tfplan_mock.py --plan infra/aws-core/terraform/environments/dev/plan.json
opa eval \
  --fail-defined \
  --data infra/policies/opa \
  --input infra/aws-core/terraform/environments/dev/plan.json \
  "data.terraform.kms.deny"
sentinel apply \
  -config infra/policies/sentinel/dev.hcl \
  infra/policies/sentinel/kms.sentinel
terraform -chdir=infra/aws-core/terraform/environments/dev show -no-color plan.tfplan | platform/scripts/assert-no-cmk.sh
rm -f infra/aws-core/terraform/environments/dev/plan.json infra/policies/sentinel/mocks/dev-plan.sentinel
```

Fix any resulting deny messages by removing `aws_kms_key` resources or converting the workload to use AWS-managed encryption.
