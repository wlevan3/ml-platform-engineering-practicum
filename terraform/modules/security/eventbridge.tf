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
  # GuardDuty severity threshold (numeric-based)
  # GuardDuty only supports 0.1-8.9 (LOW: 0.1-3.9, MEDIUM: 4.0-6.9, HIGH: 7.0-8.9)
  # Note: GuardDuty has NO "CRITICAL" severity level
  # Security Hub may re-score GuardDuty HIGH findings as CRITICAL
  guardduty_alert_severity_min = 7.0
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

# EventBridge Rule: GuardDuty HIGH severity findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count = var.enable_guardduty ? 1 : 0

  name        = "${var.cluster_name}-guardduty-high-findings"
  description = "Capture GuardDuty HIGH severity findings (7.0-8.9)"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{
        numeric = [">=", local.guardduty_alert_severity_min]
      }]
    }
  })

  tags = local.tags
}

# EventBridge Target: Send GuardDuty findings to SNS
resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  count = var.enable_guardduty ? 1 : 0

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
