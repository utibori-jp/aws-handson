# =============================================================================
# sns.tf — guardduty-threat-detection
# GuardDuty アラート通知用の SNS トピック。
# EventBridge からの publish を許可するトピックポリシーを設定する。
# =============================================================================

resource "aws_sns_topic" "guardduty_alerts" {
  name = "${var.project_name}-guardduty-alerts"

  tags = {
    Name = "${var.project_name}-guardduty-alerts"
  }
}

# SNS トピックポリシー。
# EventBridge（events.amazonaws.com）が Publish できるように許可する。
# Confused Deputy 対策として aws:SourceAccount 条件を付与する。
resource "aws_sns_topic_policy" "guardduty_alerts" {
  arn = aws_sns_topic.guardduty_alerts.arn

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
        Resource = aws_sns_topic.guardduty_alerts.arn
        Condition = {
          StringEquals = {
            # 自アカウントの EventBridge からの Publish のみを許可する。
            # 別アカウントの EventBridge に悪用されることを防ぐ（Confused Deputy 対策）。
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# メール通知サブスクリプション（var.alert_email が空の場合は作成しない）。
# apply 後に確認メール（Subscription Confirmation）が届くため、
# メール内のリンクをクリックして購読を確認すること。
# 確認前は "PendingConfirmation" 状態でメッセージは届かない。
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.guardduty_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
