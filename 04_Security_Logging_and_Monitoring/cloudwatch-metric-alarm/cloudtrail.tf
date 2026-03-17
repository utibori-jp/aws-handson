# =============================================================================
# cloudtrail.tf — cloudwatch-metric-alarm
# CloudTrail ログを CloudWatch Logs へ配信するための Trail と関連リソース。
# 00_Baseline の Trail とは独立した Trail をこのモジュール内で作成する。
#
# 【CloudTrail → CloudWatch Logs の仕組み】
# CloudTrail は API コールを記録する。
# CloudWatch Logs へ配信することで、メトリクスフィルターでログを集計し、
# 特定イベント（ルートログイン・セキュリティグループ変更など）を検知できる。
# このパイプラインが CIS AWS Foundations Benchmark のコアコントロール（SCS 頻出）。
# =============================================================================

# ---
# CloudWatch Logs グループ
# ---

# CloudTrail ログの配信先ロググループ。
# retention_in_days で保持期間を設定する（無制限にすると CloudWatch Logs のコストが増える）。
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = local.log_group_name
  retention_in_days = 90

  tags = {
    Name = local.log_group_name
  }
}

# ---
# CloudTrail → CloudWatch Logs 書き込み用 IAM ロール
# ---

# CloudTrail が CloudWatch Logs へログを書き込むために AssumeRole するロール。
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-cloudtrail-cw-role"
  }
}

# CloudTrail が CloudWatch Logs グループに書き込むためのインラインポリシー。
# CreateLogStream と PutLogEvents の2つの権限が必要（AWS 公式ドキュメント準拠）。
resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cw-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        # 特定のロググループにのみ書き込みを許可する（最小権限原則）。
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

# ---
# CloudTrail ログ用 S3 バケット
# ---

# CloudTrail のログファイル保管先バケット。
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-cw-metrics-trail"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-cw-metrics-trail"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrail が S3 バケットへ書き込むために必要なバケットポリシー。
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket     = aws_s3_bucket.cloudtrail.id
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
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

resource "aws_cloudtrail" "cis" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  # IAM・Route53 などグローバルサービスのイベントも記録する。
  # CIS ベンチマークはグローバルサービスイベントの記録を要求している。
  include_global_service_events = true

  # マルチリージョン証跡にすることで、全リージョンの API コールを1つの Trail で収集できる。
  is_multi_region_trail = true

  # ログ整合性検証を有効化（改ざん検知）。
  enable_log_file_validation = true

  # CloudWatch Logs への配信設定。
  # この設定があることで CloudTrail ログをメトリクスフィルターの入力として使用できる。
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  # バケットポリシーが先に存在しないと Trail 作成が失敗するため明示的に依存関係を宣言する。
  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = {
    Name = local.trail_name
  }
}
