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

# SNS トピックポリシーの定義。
# CloudWatch Alarms（cloudwatch.amazonaws.com）と EventBridge（events.amazonaws.com）の
# 両サービスが Publish できるように許可する。
# このモジュールは「メトリクスフィルター方式」と「EventBridge 直接検知方式」の2方式を
# 同一 SNS トピックに集約する設計のため、両プリンシパルを許可する。
# aws:SourceAccount 条件で Confused Deputy 攻撃を防止する。
data "aws_iam_policy_document" "cis_alarms_policy" {
  statement {
    sid    = "AllowCloudWatchPublic"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.cis_alarms.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.cis_alarms.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

}

# 上記ポリシードキュメントを SNS トピックにアタッチする。
resource "aws_sns_topic_policy" "cis_alarms" {
  arn = aws_sns_topic.cis_alarms.arn

  policy = data.aws_iam_policy_document.cis_alarms_policy.json
}

# メール通知サブスクリプション（var.alert_email が空の場合は作成しない）。
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.cis_alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
