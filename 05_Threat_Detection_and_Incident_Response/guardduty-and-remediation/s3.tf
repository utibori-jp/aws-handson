# =============================================================================
# s3.tf — guardduty-and-remediation
# GuardDuty カスタム脅威インテリジェンスリストを配置する S3 バケット。
#
# 【カスタム脅威インテリジェンスリストとは】
# GuardDuty は AWS が管理する脅威インテリジェンス（既知の悪性 IP・ドメイン）を標準で持つ。
# カスタムリストを追加することで、自組織が把握している攻撃者 IP や C2 サーバーを
# 独自に登録し、検知精度を高めることができる（SCS 頻出）。
#
# 【ThreatIntelSet と IPSet の違い】
# - ThreatIntelSet: 既知の悪性 IP リスト。このリストの IP と通信があると finding を生成する。
# - IPSet（Trusted IP）: 誤検知除外リスト。このリストの IP は finding を生成しない。
#   例）自社のオフィス IP からの操作を GuardDuty が攻撃と誤検知しないようにするため。
#
# 【IPアドレスの注意】
# ダミー IP は RFC 5737 の TEST-NET（192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24）を使用。
# これらはドキュメント・テスト目的用に予約されており、実際の通信には使われない。
# =============================================================================

resource "aws_s3_bucket" "threat_intel" {
  bucket = "${var.project_name}-guardduty-intel-${local.account_id}"

  # ハンズオン終了後に terraform destroy でバケットを削除できるようにする。
  force_destroy = true

  tags = {
    Name = "${var.project_name}-guardduty-intel"
  }
}

resource "aws_s3_bucket_public_access_block" "threat_intel" {
  bucket = aws_s3_bucket.threat_intel.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# GuardDuty サービスがバケットからリストを読み込めるようにバケットポリシーを設定する。
# GuardDuty はサービスリンクロールで S3 にアクセスするため、このポリシーが必要。
resource "aws_s3_bucket_policy" "threat_intel" {
  bucket = aws_s3_bucket.threat_intel.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGuardDutyRead"
        Effect = "Allow"
        Principal = {
          Service = "guardduty.amazonaws.com"
        }
        Action = [
          "s3:GetObject",
          "s3:GetBucketLocation",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.threat_intel.arn,
          "${aws_s3_bucket.threat_intel.arn}/*",
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.threat_intel]
}

# 脅威 IP リスト（ThreatIntelSet 用）。
# 本番では実際の悪性 IP を登録するが、ハンズオンではドキュメント用 IP（TEST-NET）を使う。
resource "aws_s3_object" "threat_ips" {
  bucket = aws_s3_bucket.threat_intel.bucket
  key    = "threat-ips.txt"

  # RFC 5737 TEST-NET アドレス（実際の通信では使われない安全なダミー IP）。
  content = <<-EOF
    192.0.2.1
    198.51.100.1
    203.0.113.1
  EOF

  content_type = "text/plain"
}

# 信頼 IP リスト（IPSet 用）。
# 自社ネットワーク等、誤検知させたくない IP を登録する。
resource "aws_s3_object" "trusted_ips" {
  bucket = aws_s3_bucket.threat_intel.bucket
  key    = "trusted-ips.txt"

  # ハンズオンでは RFC 1918 プライベートアドレス帯をサンプルとして登録する。
  content = <<-EOF
    10.0.0.0/8
    172.16.0.0/12
    192.168.0.0/16
  EOF

  content_type = "text/plain"
}
