# =============================================================================
# s3.tf — cloudfront-waf-oac
# CloudFront のオリジンとなる S3 バケット。
# OAC（Origin Access Control）を使って CloudFront 経由のアクセスのみを許可する。
#
# 【OAC（Origin Access Control）とは】
# CloudFront が S3 バケットにアクセスする際に使用する認証メカニズム。
# OAC は OAI（Origin Access Identity）の後継であり、
# SigV4 署名による認証・SSE-KMS への対応・定期的な認証情報ローテーションが改善されている。
#
# 【バケットポリシーの要点】
# - Principal: cloudfront.amazonaws.com（CloudFront サービス）のみ許可
# - aws:SourceArn 条件で「このディストリビューション以外」からのアクセスを拒否する
#   → Confused Deputy 攻撃対策（別の CloudFront ディストリビューションによる悪用防止）
# - パブリックアクセスブロックを有効にしたまま CloudFront 経由のみ公開できる点が重要
#
# 【確認ポイント】
# S3 バケットへの直接アクセスが拒否されることを確認する。
# CloudFront を経由せず S3 のリージョナルエンドポイントに直接 GET すると 403 になる。
#
#   BUCKET=$(terraform output -raw origin_bucket_name)
#   curl -si "https://${BUCKET}.s3.ap-northeast-1.amazonaws.com/index.html" | head -5
#   # → HTTP/1.1 403 Forbidden
# =============================================================================

resource "aws_s3_bucket" "origin" {
  bucket        = "${var.project_name}-cf-origin"
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-cf-origin"
    Purpose = "CloudFront-OAC-Origin"
  }
}

# パブリックアクセスを全面ブロック。
# OAC を使うことで、バケットをパブリックにしなくても CloudFront 経由で公開できる。
# 「バケットは非公開だが CloudFront 経由なら見える」という構成が OAC の核心。
resource "aws_s3_bucket_public_access_block" "origin" {
  bucket = aws_s3_bucket.origin.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "origin" {
  bucket = aws_s3_bucket.origin.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# OAC 専用バケットポリシー。
# cloudfront.amazonaws.com のみ GetObject を許可し、
# aws:SourceArn で「このディストリビューション」からのアクセスに限定する。
resource "aws_s3_bucket_policy" "origin" {
  bucket = aws_s3_bucket.origin.id

  # aws_s3_bucket_public_access_block が先に存在しないとポリシー適用が失敗する。
  depends_on = [aws_s3_bucket_public_access_block.origin]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOACAccess"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.origin.arn}/*"
        Condition = {
          StringEquals = {
            # aws:SourceArn に CloudFront ディストリビューションの ARN を指定することで、
            # 「このディストリビューション以外の CloudFront」からのアクセスを防ぐ。
            # 例: 別の顧客が同じバケットを OAC で参照しようとするケースを防ぐ。
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

# ---
# デモ用コンテンツ
# ---

# CloudFront 経由でアクセスできることを確認するためのサンプルファイル。
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.origin.id
  key          = "index.html"
  content      = "<html><body><h1>Hello from CloudFront + OAC</h1></body></html>"
  content_type = "text/html"
}
