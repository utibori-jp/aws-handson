# =============================================================================
# eventbridge.tf — macie-sensitive-data
# Macie フィンディングを EventBridge 経由で SNS に転送する。
#
# 【04章との比較】
# guardduty-threat-detection の EventBridge ルールと構造がほぼ同じ。
# source と detail-type が "aws.macie2" / "Macie Finding" に変わるだけ。
# 「同じ EventBridge パターンが GuardDuty / Macie / Config / Security Hub などで使える」
# ことがこの章を通じて体験できる（SCS 頻出：サービス横断の検出パイプライン設計）。
# =============================================================================

resource "aws_cloudwatch_event_rule" "macie_findings" {
  name        = "${var.project_name}-macie-findings"
  description = "Capture Macie findings and forward to SNS"

  event_pattern = jsonencode({
    source      = ["aws.macie2"]
    detail-type = ["Macie Finding"]
    # 全フィンディングタイプを対象にする。
    # 本番では severity でフィルタリングすることを推奨（HIGH 以上など）。
  })

  tags = {
    Name = "${var.project_name}-macie-findings"
  }
}

resource "aws_cloudwatch_event_target" "macie_to_sns" {
  rule      = aws_cloudwatch_event_rule.macie_findings.name
  target_id = "MacieToSNS"
  arn       = aws_sns_topic.macie_alerts.arn
}
