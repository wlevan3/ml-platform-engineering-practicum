# Terraform Policy Guardrails

## Customer-Managed KMS Keys

- Policy location: `policy/terraform/kms.rego`
- Sentinel policy: `policy/sentinel/kms.sentinel`
- Sentinel config: `policy/sentinel/dev.hcl`
- Enforcement: runs during the `terraform-validate` job in `.github/workflows/ci.yml`

### What it does

The OPA policy denies any Terraform plan that creates or updates an `aws_kms_key` resource with `is_enabled` set to `true` or left unset (the AWS default). Keys marked for deletion are ignored.

### Run it locally

```bash
cd terraform/environments/dev
terraform plan -out plan.tfplan
terraform show -json plan.tfplan > plan.json
cd ../../..
python3 scripts/generate_sentinel_tfplan_mock.py
opa eval \
  --fail-defined \
  --data policy/terraform \
  --input terraform/environments/dev/plan.json \
  "data.terraform.kms.deny"
sentinel apply \
  -config policy/sentinel/dev.hcl \
  policy/sentinel/kms.sentinel
rm -f terraform/environments/dev/plan.json policy/sentinel/mocks/dev-plan.sentinel
```

Fix any resulting deny messages by ensuring `is_enabled = false` or by removing the offending key before committing your changes.
