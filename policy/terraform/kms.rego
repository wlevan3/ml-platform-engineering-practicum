package terraform.kms

# Deny Terraform plans that leave customer-managed KMS keys enabled.
deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "aws_kms_key"
  rc.mode == "managed"

  # Skip resources being deleted.
  actions := rc.change.actions
  not action_is_delete(actions)

  after := rc.change.after
  after != null

  enabled := object.get(after, "is_enabled", true)
  enabled

  msg := sprintf("aws_kms_key %q must be disabled (is_enabled = false).", [rc.name])
}

action_is_delete(actions) {
  actions[_] == "delete"
}
