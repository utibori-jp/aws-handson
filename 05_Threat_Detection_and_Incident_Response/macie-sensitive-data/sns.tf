# =============================================================================
# sns.tf — macie-sensitive-data
# Macie アラート通知用 SNS トピック。
# =============================================================================

resource "aws_sns_topic" "macie_alerts" {
  name = "${var.project_name}-macie-alerts"

  tags = {
    Name = "${var.project_name}-macie-alerts"
  }
}

resource "aws_sns_topic_policy" "macie_alerts" {
  arn = aws_sns_topic.macie_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.macie_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.macie_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
