# =============================================================================
# s3.tf — kms-cmk-encryption
# CMK（Customer Managed Key）で暗号化した S3 バケット。
# SSE-KMS を使い、バケットポリシーで HTTPS のみのアクセスを強制する。
#
# 【SSE-KMS の特徴】
# - オブジェクトの暗号化/復号に KMS API が呼ばれる → CloudTrail に kms:Decrypt ログが残る
# - アクセスは IAM ポリシー + キーポリシーの両方で制御できる（二重の防御）
# - SSE-S3（AES256）と違い、「誰がいつ復号したか」を監査できる（SCS 頻出・監査要件）
#
# 【aws:SecureTransport 条件（HTTPS 強制）】
# バケットポリシーで HTTP リクエストを Deny することで、転送中の暗号化を強制する。
# "aws:SecureTransport": "false" のときに Deny することで HTTPS のみを許可する。
# SCS 試験で「転送中の暗号化を強制する方法」として頻出。
# =============================================================================

resource "aws_s3_bucket" "encrypted" {
  bucket        = "${var.project_name}-kms-encrypted"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-kms-encrypted"
  }
}

# パブリックアクセスを全面ブロック。
resource "aws_s3_bucket_public_access_block" "encrypted" {
  bucket = aws_s3_bucket.encrypted.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-KMS によるデフォルト暗号化。
# バケットに書き込まれるすべてのオブジェクトが自動で CMK で暗号化される。
resource "aws_s3_bucket_server_side_encryption_configuration" "encrypted" {
  bucket = aws_s3_bucket.encrypted.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      # CMK ARN を明示することで AWS Managed Key（aws/s3）ではなく CMK が使われる。
      kms_master_key_id = aws_kms_key.s3_cmk.arn
    }

    # S3 Bucket Key を有効化。
    # バケット単位のデータキーを生成し、KMS API 呼び出し回数（コスト）を大幅削減できる。
    # オブジェクトごとに KMS API を呼ぶ代わりに、バケットキーで再暗号化する仕組み。
    # セキュリティ特性は SSE-KMS と同等。
    bucket_key_enabled = true
  }
}

# バケットポリシー：HTTPS のみ許可 + KMS キーの明示的な使用強制。
resource "aws_s3_bucket_policy" "encrypted" {
  bucket = aws_s3_bucket.encrypted.id

  # aws_s3_bucket_public_access_block が先に存在しないとポリシー適用が失敗する。
  depends_on = [aws_s3_bucket_public_access_block.encrypted]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # HTTP（非暗号化）通信を Deny する。
        # aws:SecureTransport が false（= HTTP）のリクエストをすべて拒否。
        # Principal: "*" + Deny の組み合わせで、IAM 権限に関わらず HTTP を遮断できる（SCS 頻出）。
        Sid    = "DenyNonHTTPS"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.encrypted.arn,
          "${aws_s3_bucket.encrypted.arn}/*",
        ]
        Condition = {
          Bool = {
            # false = HTTP リクエスト
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        # SSE-S3 や SSE-KMS with AWS Managed Key を使った PutObject を Deny する。
        # CMK 以外の暗号化でオブジェクトが書き込まれることを防ぐ。
        # x-amz-server-side-encryption-aws-kms-key-id ヘッダーが CMK ARN でない場合を拒否。
        Sid    = "DenyNonCMKEncryption"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.encrypted.arn}/*"
        Condition = {
          StringNotEqualsIfExists = {
            # このヘッダーが CMK ARN でない PutObject を拒否する。
            # "IfExists" により、ヘッダーなし（SSE-S3 デフォルト）も拒否対象になる。
            "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.s3_cmk.arn
          }
        }
      }
    ]
  })
}
