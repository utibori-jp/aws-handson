# =============================================================================
# s3.tf — macie-sensitive-data
# Macie のスキャン対象 S3 バケットとテスト用ダミー PII データ。
#
# 【テストデータについて】
# ダミーの PII パターン（クレジットカード番号・SSN）を含む CSV を使用する。
# すべて架空のテスト値であり、実際の個人情報・金融情報は一切使用していない。
# - クレジットカード番号: Visa テスト番号（4111111111111111 など）
# - SSN: 000-xx-xxxx 形式（アメリカ社会保障番号の無効値）
# - メールアドレス: example.com ドメイン（RFC 2606 で予約済み）
# =============================================================================

resource "aws_s3_bucket" "macie_test" {
  bucket        = "${var.project_name}-macie-test"
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-macie-test"
    Purpose = "Macie-PII-Detection-Test"
  }
}

resource "aws_s3_bucket_public_access_block" "macie_test" {
  bucket = aws_s3_bucket.macie_test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "macie_test" {
  bucket = aws_s3_bucket.macie_test.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---
# ダミー PII データ（テスト用）
# ---

# Macie のビルトイン managed data identifier が検出するパターンを含むテスト CSV。
# クレジットカード番号（CREDIT_CARD_NUMBER）と SSN（US_SOCIAL_SECURITY_NUMBER）が
# Macie によって検出されることを確認する。
resource "aws_s3_object" "dummy_pii_csv" {
  bucket       = aws_s3_bucket.macie_test.id
  key          = "customer-data/test-customers.csv"
  content_type = "text/csv"

  # すべて架空のテスト値。実際の個人情報は含まない。
  content = <<-CSV
    customer_id,name,email,credit_card,ssn,notes
    1001,Test User A,test-a@example.com,4111111111111111,000-12-3456,dummy record for macie test
    1002,Test User B,test-b@example.com,5500005555555559,000-23-4567,dummy record for macie test
    1003,Test User C,test-c@example.com,378282246310005,000-34-5678,dummy record for macie test
  CSV

  tags = {
    Purpose = "Macie-Detection-Test"
    Note    = "Contains dummy PII patterns for Macie scanning — not real personal data"
  }
}

# Macie の管理者がバケットを読み取るために必要なバケットポリシー。
# Macie サービスロールがオブジェクトを読み取れるよう許可する。
resource "aws_s3_bucket_policy" "macie_test" {
  bucket     = aws_s3_bucket.macie_test.id
  depends_on = [aws_s3_bucket_public_access_block.macie_test]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMacieRead"
        Effect = "Allow"
        Principal = {
          Service = "macie.amazonaws.com"
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.macie_test.arn,
          "${aws_s3_bucket.macie_test.arn}/*",
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}
