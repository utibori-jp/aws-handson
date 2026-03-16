# =============================================================================
# cloudtrail.tf — cloudtrail-base
# マルチリージョン対応のCloudTrail証跡を有効化し、S3バケットへログを集約する。
# ログファイルの整合性検証を有効にし、改ざん検知を担保する。
# =============================================================================

# account_id / partition は main.tf で定義。trail_name はこのファイル固有のため個別に定義する。
locals {
  trail_name = "${var.project_name}-trail"
}

# ---
# S3バケット（ログ集約先）
# ---

# CloudTrailのログ保管先バケット。
# S3バケット名はグローバルでユニークである必要があるが、ハンズオン用途として
# project_name を自分固有の名前に設定することでユニーク性を担保する想定。
# force_destroy = true は学習用として terraform destroy を容易にするための設定。
# 本番環境ではログ保全の観点から false にすること。
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-cloudtrail"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-cloudtrail"
  }
}

# バージョニングを有効化。
# ログファイルが上書き・削除された場合に旧バージョンを復元できるようにする。
resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

# サーバーサイド暗号化（SSE-S3）を有効化。
# KMSを使うとCloudTrailがPutObjectする際にkms:GenerateDataKey権限が必要になり
# キーポリシーの設定が複雑になるため、ベースラインではAES256（SSE-S3）を採用する。
# KMSを使った暗号化は03章で扱う。
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# パブリックアクセスを全面ブロック。
# ログバケットが誤って公開されることを防ぐ。SCSの頻出テーマ。
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrailがバケットへ書き込むために必要なバケットポリシー。
# AWSが要求する2つのStatementを設定する（公式ドキュメント準拠）。
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudTrailサービスがログを書き込む前に、「自分に権限があるか」「バケット所有者は誰か」を
        # バケットのACLを確認するために必要。
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
        # AWS:SourceArn 条件を付けることで、自分の証跡以外からの操作を拒否する。
        # これは「Confused Deputy問題」への対策（別アカウントのCloudTrailに悪用されることを防ぐ）。
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"
          }
        }
      },
      {
        # CloudTrailがログファイルをPutObjectするために必要。
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "s3:PutObject"
        # AWSLogs/{account_id}/ 以下のみに書き込みを許可。
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            # bucket-owner-full-control はログの所有権をバケット所有者（監査アカウントなど）に移譲するための設定。
            # 各アカウントのCloudtrailログは、共通のこのバケットに集約される。
            # この設定がないと、バケット所有者が自分のバケット内に他アカウントから書き込まれたログにアクセスできなくなる。
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"
          }
        }
      }
    ]
  })
}

# ---
# CloudTrail 証跡
# ---

resource "aws_cloudtrail" "main" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  # IAMやRoute53などグローバルサービスのAPIコールも記録する。
  include_global_service_events = true

  # 全リージョンのイベントを1つの証跡で収集する。
  # リージョンごとに証跡を作る必要がなく、管理が集約できる。
  is_multi_region_trail = true

  # ログファイルの整合性検証を有効化。
  # ダイジェストファイルを使ってログが改ざんされていないかを検証できる（SCS頻出）。
  enable_log_file_validation = true

  # バケットポリシーが先に存在しないとCloudTrailの作成が失敗するため、明示的に依存関係を宣言する。
  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = {
    Name = local.trail_name
  }
}
