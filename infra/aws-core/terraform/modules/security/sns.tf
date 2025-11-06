# ===================================================================
# SNS Topic for Security Alerts
# ===================================================================
#
# Creates an encrypted SNS topic for security finding notifications.
# EventBridge rules send HIGH/CRITICAL findings to this topic.
# ===================================================================

# SNS topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  count = var.enable_security_hub || var.enable_guardduty ? 1 : 0

  name         = local.sns_topic_name
  display_name = "ML Platform Security Alerts"

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
