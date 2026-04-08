# =============================================================================
# sns.tf — guardduty-and-remediation
# 修復実行時の通知 SNS トピック。
# Lambda が自動修復を実行した際に管理者へ通知する。
# =============================================================================

resource "aws_sns_topic" "remediation_alerts" {
  name = "${var.project_name}-remediation-alerts"

  tags = {
    Name = "${var.project_name}-remediation-alerts"
  }
}

# Lambda（EventBridge 経由ではなく Lambda 自身）が SNS に Publish するため、
# リソースポリシーではなく IAM ロールで制御する。
# このトピックポリシーは Lambda から直接 Publish するため最小限の設定。
resource "aws_sns_topic_policy" "remediation_alerts" {
  arn = aws_sns_topic.remediation_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.cancel_kms_deletion.arn,
            aws_iam_role.revoke_sg_ingress.arn,
            aws_iam_role.remediate_iam_key.arn,
            aws_iam_role.isolate_ec2.arn,
          ]
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.remediation_alerts.arn
      }
    ]
  })
}

# メールサブスクリプション（alert_email が指定された場合のみ作成）。
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.remediation_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
