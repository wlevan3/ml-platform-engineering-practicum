# ===================================================================
# AWS Security Monitoring Module
# ===================================================================
#
# This module provides centralized security monitoring using:
# - AWS Security Hub (CIS Benchmark, AWS Foundational Security)
# - AWS GuardDuty (threat detection)
# - AWS Inspector (vulnerability scanning)
# - EventBridge + SNS (automated alerting)
#
# Resources are conditionally created based on enable_* variables
# to support cost optimization and phased rollouts.
# ===================================================================

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Local variables for common values
locals {
  # Resource naming
  security_prefix = "${var.cluster_name}-security"
  sns_topic_name  = "${var.cluster_name}-security-alerts"
  kms_key_alias   = "alias/${var.cluster_name}-sns"

  # Alert configuration
  alert_severities = ["HIGH", "CRITICAL"]

  # Common tags
  tags = merge(
    var.tags,
    {
      Module = "security"
    }
  )
}

# ===================================================================
# AWS Security Hub
# ===================================================================

# Enable Security Hub for centralized security findings
resource "aws_securityhub_account" "main" {
  count = var.enable_security_hub ? 1 : 0

  enable_default_standards  = false # We enable standards explicitly below
  control_finding_generator = "SECURITY_CONTROL"
}

# CIS AWS Foundations Benchmark v1.4.0
resource "aws_securityhub_standards_subscription" "cis" {
  count = var.enable_security_hub && var.enable_cis_standard ? 1 : 0

  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
}

# AWS Foundational Security Best Practices v1.0.0
resource "aws_securityhub_standards_subscription" "foundational" {
  count = var.enable_security_hub && var.enable_foundational_security ? 1 : 0

  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# ===================================================================
# AWS GuardDuty
# ===================================================================

# Enable GuardDuty for threat detection
#checkov:skip=CKV_AWS_238:GuardDuty is conditionally enabled for cost optimization - disabled by default in dev environments (~$10-30/month after 30-day free trial), enable via enable_guardduty variable when ready for continuous threat detection
resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable = true

  # Publish findings every 15 minutes (fastest option)
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = local.tags
}

resource "aws_guardduty_detector_feature" "s3_data_events" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.main[0].id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "kubernetes_audit_logs" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.main[0].id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.main[0].id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

# ===================================================================
# AWS Inspector
# ===================================================================

# Enable Inspector v2 for vulnerability scanning
# Automatically discovers EC2 instances and ECR images
resource "aws_inspector2_enabler" "main" {
  count = var.enable_inspector ? 1 : 0

  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2", "ECR"]
}
