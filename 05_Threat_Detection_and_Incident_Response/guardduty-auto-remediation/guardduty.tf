# =============================================================================
# guardduty.tf — guardduty-auto-remediation
# GuardDuty Detector の有効化。
#
# ⚠️ 04章の guardduty-threat-detection を apply 済みの場合：
#    GuardDuty Detector は 1 リージョンにつき 1 つしか作成できない。
#    このモジュールを apply する前に、04章の guardduty-threat-detection を
#    terraform destroy してから実行すること。
#    → 詳細は章 README の「前提条件」セクションを参照。
# =============================================================================

resource "aws_guardduty_detector" "main" {
  enable = true

  # 15 分ごとにフィンディングを発行する。
  # ハンズオンで create-sample-findings → Lambda 実行を素早く確認するための設定。
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "${var.project_name}-guardduty"
  }
}
