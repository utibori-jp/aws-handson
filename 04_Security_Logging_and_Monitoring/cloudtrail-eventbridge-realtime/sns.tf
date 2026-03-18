# =============================================================================
# sns.tf — cloudtrail-eventbridge-realtime
# CloudTrail 危険 API の即時アラートを受け取る SNS トピックを定義する。
# =============================================================================

# リアルタイムアラート用の SNS トピック。
# EventBridge ルールがここにメッセージを Publish する。
resource "aws_sns_topic" "cloudtrail_alerts" {
  name = "${var.project_name}-cloudtrail-alerts"

  tags = {
    Name = "${var.project_name}-cloudtrail-alerts"
  }
}

# EventBridge がこのトピックに Publish できるようにリソースポリシーを設定する。
# SNS トピックはデフォルトでアカウント内の IAM プリンシパルからの Publish を許可しているが、
# EventBridge（サービスプリンシパル）からの Publish には明示的なリソースポリシーが必要。
resource "aws_sns_topic_policy" "cloudtrail_alerts" {
  arn = aws_sns_topic.cloudtrail_alerts.arn

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
        Resource = aws_sns_topic.cloudtrail_alerts.arn
        # SourceAccount 条件で自アカウントの EventBridge のみに限定する。
        # 他アカウントの EventBridge から悪用されることを防ぐ。
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# メール通知のサブスクリプション（alert_email が指定された場合のみ作成）。
# apply 後に確認メールが届くため、リンクをクリックして購読を有効化すること。
# 購読前は "PendingConfirmation" 状態で通知は届かない。
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.cloudtrail_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
