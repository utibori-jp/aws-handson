# =============================================================================
# s3.tf
# SSM Session Manager のセッションログ保存先 S3 バケットと KMS CMK。
#
# SCS 的観点:
#   - CMK (Customer Managed Key) を使うことで鍵のローテーション・ポリシーを自分で管理できる。
#   - バケットポリシーで HTTPS 必須 (aws:SecureTransport) を強制する。
#   - PutObject を EC2 IAM ロールのみに限定し、過剰な書き込みを防ぐ。
# =============================================================================

# --- KMS CMK ---

resource "aws_kms_key" "session_logs" {
  description             = "CMK for SSM Session Manager session logs"
  enable_key_rotation     = true  # 年次自動ローテーション — コンプライアンス要件でよく求められる
  deletion_window_in_days = 7     # 最短の削除保護期間（ハンズオン環境向けに短縮）

  # キーポリシー: デフォルトのキーポリシーを使用（root ユーザーにフルアクセス）。
  # 本番では特定の IAM ロールのみに kms:GenerateDataKey を許可すべき。
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${local.partition}:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # EC2 ロールがセッションログを暗号化するために必要。
        Sid    = "AllowEC2SessionLogEncryption"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ec2.arn
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-session-logs-key"
  }
}

resource "aws_kms_alias" "session_logs" {
  name          = "alias/${var.project_name}-session-logs"
  target_key_id = aws_kms_key.session_logs.key_id
}

# --- S3 バケット ---

resource "aws_s3_bucket" "session_logs" {
  # バケット名にアカウント ID を含めてグローバルユニーク性を担保する。
  bucket = "${var.project_name}-session-logs-${local.account_id}"

  # Terraform で管理する学習用バケット。
  # 本番では RETAIN または保護ポリシーを検討すること。
  force_destroy = true

  tags = {
    Name = "${var.project_name}-session-logs"
  }
}

# パブリックアクセスを全てブロック。セッションログに外部からアクセスできてはならない。
resource "aws_s3_bucket_public_access_block" "session_logs" {
  bucket                  = aws_s3_bucket.session_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# バージョニング: ログの改ざん検知・誤削除時の復元に有効。
resource "aws_s3_bucket_versioning" "session_logs" {
  bucket = aws_s3_bucket.session_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-KMS でサーバーサイド暗号化。CMK を指定することで鍵管理を自分で行える。
# SSE-S3 (AES256) より管理性が高く、CloudTrail で鍵の使用履歴も追跡できる。
resource "aws_s3_bucket_server_side_encryption_configuration" "session_logs" {
  bucket = aws_s3_bucket.session_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.session_logs.arn
    }
    bucket_key_enabled = true # KMS API コール数を削減してコストを抑える
  }
}

# バケットポリシー: HTTPS 必須 + EC2 ロールのみ書き込み可。
resource "aws_s3_bucket_policy" "session_logs" {
  bucket = aws_s3_bucket.session_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # HTTPS (TLS) 以外での通信を拒否。転送中の暗号化を強制する。
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.session_logs.arn,
          "${aws_s3_bucket.session_logs.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        # EC2 IAM ロールのみがアカウント ID プレフィックス配下に書き込める。
        # 他のサービスや IAM ユーザーからの書き込みを防ぐ。
        Sid    = "AllowSSMSessionLogging"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ec2.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.session_logs.arn}/${local.account_id}/*"
      }
    ]
  })
}
