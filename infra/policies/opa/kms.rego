import rego.v1

package terraform.kms

# Deny Terraform plans that introduce customer-managed KMS keys.
deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "aws_kms_key"
  rc.mode == "managed"

  # Skip resources scheduled for deletion.
  actions := rc.change.actions
  not action_is_delete(actions)

  msg := sprintf("aws_kms_key %q is not allowed. Use AWS-managed encryption instead.", [rc.address])
}

action_is_delete(actions) if {
  actions != null
  "delete" in actions
}
