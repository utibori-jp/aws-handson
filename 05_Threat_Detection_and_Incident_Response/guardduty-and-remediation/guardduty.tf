# =============================================================================
# guardduty.tf — guardduty-and-remediation
# GuardDuty Detector の有効化とカスタム脅威インテリジェンスの登録。
#
# 【GuardDuty の検知ソース】
# GuardDuty は以下のデータソースを自動的に分析して脅威を検知する：
# - CloudTrail 管理イベント（API 呼び出しの異常）
# - VPC Flow Logs（異常な通信パターン）
# - DNS ログ（C2 ドメインへの問い合わせ）
# これらのログを自前で有効化・保存する必要はなく、GuardDuty が裏側で処理する。
#
# 【finding_publishing_frequency について】
# GuardDuty は新規 finding をまとめて EventBridge に発行する。
# FIFTEEN_MINUTES: 15 分ごと（ハンズオンで素早く確認できる設定）
# ONE_HOUR / SIX_HOURS: 本番向け（コスト最適化）
# =============================================================================

resource "aws_guardduty_detector" "main" {
  enable = true

  # 15 分ごとにフィンディングを発行する。
  # ハンズオンで create-sample-findings → Lambda 実行 → SNS 通知を素早く確認するための設定。
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "${var.project_name}-guardduty"
  }
}

# ---------------------------------------------------------------------------
# カスタム脅威インテリジェンスリスト（ThreatIntelSet）
# ---------------------------------------------------------------------------

# S3 上の IP リストを GuardDuty に登録する。
# このリストの IP と通信があると GuardDuty が finding を生成する。
# ハンズオンではダミー IP のため実際には finding は生成されないが、
# 登録フローとコンソールでの確認を体験できる。
resource "aws_guardduty_threatintelset" "custom" {
  activate    = true
  detector_id = aws_guardduty_detector.main.id
  format      = "TXT"
  location    = "s3://${aws_s3_bucket.threat_intel.bucket}/${aws_s3_object.threat_ips.key}"
  name        = "${var.project_name}-threat-ips"

  depends_on = [aws_s3_bucket_policy.threat_intel]

  tags = {
    Name = "${var.project_name}-threat-ips"
  }
}

# ---------------------------------------------------------------------------
# 信頼 IP セット（IPSet）
# ---------------------------------------------------------------------------

# 自社ネットワーク等、誤検知させたくない IP を GuardDuty に登録する。
# このリストに登録した IP からの通信は finding を生成しない。
# 本番では自社オフィス IP・VPN IP 等を登録する。
resource "aws_guardduty_ipset" "trusted" {
  activate    = true
  detector_id = aws_guardduty_detector.main.id
  format      = "TXT"
  location    = "s3://${aws_s3_bucket.threat_intel.bucket}/${aws_s3_object.trusted_ips.key}"
  name        = "${var.project_name}-trusted-ips"

  depends_on = [aws_s3_bucket_policy.threat_intel]

  tags = {
    Name = "${var.project_name}-trusted-ips"
  }
}
