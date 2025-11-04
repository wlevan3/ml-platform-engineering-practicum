# ===================================================================
# EventBridge Rules for Security Finding Alerts
# ===================================================================
#
# Creates EventBridge rules to capture HIGH/CRITICAL findings from:
# - AWS Security Hub
# - AWS GuardDuty
#
# Rules forward findings to SNS for email notifications.
# ===================================================================

locals {
  # GuardDuty severity ranges (simplified)
  # HIGH: 7.0-8.9, CRITICAL: 9.0-10.0
  guardduty_high_severities     = [for i in range(70, 90) : i / 10.0]
  guardduty_critical_severities = [for i in range(90, 101) : i / 10.0]
  guardduty_alert_severities    = concat(local.guardduty_high_severities, local.guardduty_critical_severities)
}

# ===================================================================
# Security Hub EventBridge Rules
# ===================================================================

# EventBridge Rule: Security Hub HIGH/CRITICAL findings
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  count = var.enable_security_hub ? 1 : 0

  name        = "${var.cluster_name}-security-hub-critical-findings"
  description = "Capture Security Hub HIGH and CRITICAL severity findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = local.alert_severities
        }
        Workflow = {
          Status = ["NEW"]
        }
      }
    }
  })

  tags = local.tags
}

# EventBridge Target: Send Security Hub findings to SNS
resource "aws_cloudwatch_event_target" "security_hub_to_sns" {
  count = var.enable_security_hub ? 1 : 0

  rule      = aws_cloudwatch_event_rule.security_hub_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts[0].arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.findings[0].Severity.Label"
      title       = "$.detail.findings[0].Title"
      description = "$.detail.findings[0].Description"
      resource    = "$.detail.findings[0].Resources[0].Id"
      region      = "$.detail.findings[0].Resources[0].Region"
      compliance  = "$.detail.findings[0].Compliance.Status"
      account     = "$.detail.findings[0].AwsAccountId"
    }

    input_template = <<-EOT
    "🚨 Security Hub Alert: <severity> Severity Finding"
    ""
    "Title: <title>"
    ""
    "Description: <description>"
    ""
    "Resource: <resource>"
    "Region: <region>"
    "Account: <account>"
    "Compliance Status: <compliance>"
    ""
    "Action Required: Review finding in AWS Security Hub console"
    "Console: https://<region>.console.aws.amazon.com/securityhub/"
    EOT
  }
}

# ===================================================================
# GuardDuty EventBridge Rules
# ===================================================================

# EventBridge Rule: GuardDuty HIGH/CRITICAL findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count = var.enable_guardduty ? 1 : 0

  name        = "${var.cluster_name}-guardduty-critical-findings"
  description = "Capture GuardDuty HIGH and CRITICAL severity findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = local.guardduty_alert_severities
    }
  })

  tags = local.tags
}

# EventBridge Target: Send GuardDuty findings to SNS
resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  count = var.enable_guardduty && var.enable_security_hub ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts[0].arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      title       = "$.detail.title"
      type        = "$.detail.type"
      description = "$.detail.description"
      resource    = "$.detail.resource.instanceDetails.instanceId"
      region      = "$.region"
      finding_id  = "$.detail.id"
      account     = "$.account"
    }

    input_template = <<-EOT
    "🚨 GuardDuty Alert: Severity <severity> (<title>)"
    ""
    "Finding Type: <type>"
    "Description: <description>"
    ""
    "Resource: <resource>"
    "Region: <region>"
    "Account: <account>"
    "Finding ID: <finding_id>"
    ""
    "Action Required: Review finding in AWS GuardDuty console"
    "Console: https://<region>.console.aws.amazon.com/guardduty/"
    EOT
  }
}
