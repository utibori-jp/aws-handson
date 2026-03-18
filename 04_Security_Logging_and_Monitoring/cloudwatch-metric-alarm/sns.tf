# =============================================================================
# sns.tf — cloudwatch-metric-alarm
# CIS アラーム通知用の SNS トピック。
# CloudWatch がアラーム状態に遷移したときに Publish できるようにポリシーを設定する。
# =============================================================================

resource "aws_sns_topic" "cis_alarms" {
  name = "${var.project_name}-cis-alarms"

  tags = {
    Name = "${var.project_name}-cis-alarms"
  }
}

# SNS トピックポリシー。
# CloudWatch Alarms（cloudwatch.amazonaws.com）が Publish できるように許可する。
resource "aws_sns_topic_policy" "cis_alarms" {
  arn = aws_sns_topic.cis_alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.cis_alarms.arn
        Condition = {
          StringEquals = {
            # 自アカウントの CloudWatch からの Publish のみを許可する（Confused Deputy 対策）。
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# メール通知サブスクリプション（var.alert_email が空の場合は作成しない）。
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.cis_alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
