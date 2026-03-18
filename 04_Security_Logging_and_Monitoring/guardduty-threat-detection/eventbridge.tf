# =============================================================================
# eventbridge.tf — guardduty-threat-detection
# EventBridge ルールで GuardDuty フィンディングを捕捉し、SNS へ転送する。
#
# 【イベントパイプラインの構成】
# GuardDuty フィンディング
#   → EventBridge（ルールでフィルタリング）
#     → SNS トピック
#       → メール通知（サブスクリプションが設定されている場合）
#
# 【EventBridge とは】
# AWS サービスが発するイベントをルールでフィルタリングし、
# ターゲット（SNS / Lambda / SQS など）にルーティングするサービス。
# 旧称「CloudWatch Events」。GuardDuty / Security Hub / Config との連携に使われる（SCS 頻出）。
# =============================================================================

# GuardDuty フィンディング検出時に発火する EventBridge ルール。
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.project_name}-guardduty-findings"
  description = "Capture all GuardDuty findings and forward to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    # severity フィルタなしで全フィンディングを対象にする。
    # 本番環境では severity >= 4（MEDIUM 以上）に絞ることでノイズを削減できる：
    # "detail" = { "severity" = [{ "numeric" = [">=", 4] }] }
  })

  tags = {
    Name = "${var.project_name}-guardduty-findings"
  }
}

# EventBridge ルールのターゲットとして SNS トピックを設定する。
resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "GuardDutyToSNS"
  arn       = aws_sns_topic.guardduty_alerts.arn
}
