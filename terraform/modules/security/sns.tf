# ===================================================================
# SNS Topic for Security Alerts
# ===================================================================
#
# Creates an encrypted SNS topic for security finding notifications.
# EventBridge rules send HIGH/CRITICAL findings to this topic.
# ===================================================================

# KMS key for SNS topic encryption
resource "aws_kms_key" "sns" {
  count = var.enable_security_hub || var.enable_guardduty ? 1 : 0

  description             = "KMS key for ${local.sns_topic_name} encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow EventBridge to use the key"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow SNS to use the key"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name = "${local.security_prefix}-kms"
    }
  )
}

# KMS key alias for easier identification
resource "aws_kms_alias" "sns" {
  count = var.enable_security_hub || var.enable_guardduty ? 1 : 0

  name          = local.kms_key_alias
  target_key_id = aws_kms_key.sns[0].key_id
}

# SNS topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  count = var.enable_security_hub || var.enable_guardduty ? 1 : 0

  name              = local.sns_topic_name
  display_name      = "ML Platform Security Alerts"
  kms_master_key_id = aws_kms_key.sns[0].id

  tags = merge(
    local.tags,
    {
      Name = local.sns_topic_name
    }
  )
}

# SNS topic policy - Allow EventBridge to publish
resource "aws_sns_topic_policy" "security_alerts" {
  count = var.enable_security_hub || var.enable_guardduty ? 1 : 0

  arn = aws_sns_topic.security_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_alerts[0].arn
      }
    ]
  })
}

# Email subscription for security alerts
resource "aws_sns_topic_subscription" "security_alerts_email" {
  count = (var.enable_security_hub || var.enable_guardduty) && var.security_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}
