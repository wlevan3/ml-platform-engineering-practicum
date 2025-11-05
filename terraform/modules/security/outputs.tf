# ===================================================================
# Security Module Outputs
# ===================================================================

# Security Hub Outputs
output "security_hub_enabled" {
  description = "Whether AWS Security Hub is enabled"
  value       = var.enable_security_hub
}

output "security_hub_account_id" {
  description = "Security Hub account ID (if enabled)"
  value       = var.enable_security_hub ? try(aws_securityhub_account.main[0].id, null) : null
}

output "security_hub_standards" {
  description = "Map of enabled Security Hub standards"
  value = var.enable_security_hub ? {
    cis_benchmark         = var.enable_cis_standard
    foundational_security = var.enable_foundational_security
  } : null
}

output "security_hub_console_url" {
  description = "URL to Security Hub console in AWS Management Console"
  value       = var.enable_security_hub ? "https://${var.region}.console.aws.amazon.com/securityhub/home?region=${var.region}#/summary" : null
}

# GuardDuty Outputs
output "guardduty_enabled" {
  description = "Whether AWS GuardDuty is enabled"
  value       = var.enable_guardduty
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID (if enabled)"
  value       = var.enable_guardduty ? try(aws_guardduty_detector.main[0].id, null) : null
}

output "guardduty_console_url" {
  description = "URL to GuardDuty console in AWS Management Console"
  value       = var.enable_guardduty ? "https://${var.region}.console.aws.amazon.com/guardduty/home?region=${var.region}#/findings" : null
}

# Inspector Outputs
output "inspector_enabled" {
  description = "Whether AWS Inspector is enabled"
  value       = var.enable_inspector
}

# SNS Outputs
output "security_alerts_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = (var.enable_security_hub || var.enable_guardduty) ? try(aws_sns_topic.security_alerts[0].arn, null) : null
}

output "security_alerts_topic_name" {
  description = "Name of the SNS topic for security alerts"
  value       = (var.enable_security_hub || var.enable_guardduty) ? try(aws_sns_topic.security_alerts[0].name, null) : null
}

output "kms_key_id" {
  description = "ID of the KMS key used for SNS topic encryption"
  value       = (var.enable_security_hub || var.enable_guardduty) ? try(aws_kms_key.sns[0].id, null) : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for SNS topic encryption"
  value       = (var.enable_security_hub || var.enable_guardduty) ? try(aws_kms_key.sns[0].arn, null) : null
}

# EventBridge Outputs
output "eventbridge_rules" {
  description = "Map of EventBridge rule names and ARNs"
  value = {
    security_hub = var.enable_security_hub ? try(aws_cloudwatch_event_rule.security_hub_findings[0].arn, null) : null
    guardduty    = var.enable_guardduty ? try(aws_cloudwatch_event_rule.guardduty_findings[0].arn, null) : null
  }
}
