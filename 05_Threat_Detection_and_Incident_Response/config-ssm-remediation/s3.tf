# =============================================================================
# s3.tf — config-ssm-remediation
# Config スナップショットおよび履歴ログの保管先 S3 バケット。
# Config Delivery Channel が設定変更のスナップショットをここに書き込む。
# =============================================================================

resource "aws_s3_bucket" "config_logs" {
  bucket        = "${var.project_name}-config-logs"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-config-logs"
  }
}

resource "aws_s3_bucket_versioning" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Config サービスがバケットへ書き込むために必要なバケットポリシー。
resource "aws_s3_bucket_policy" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_logs.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_logs.arn}/AWSLogs/${local.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# ---
# Config Recorder 用 IAM ロール
# ---

resource "aws_iam_role" "config_recorder" {
  name = "${var.project_name}-config-recorder-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-config-recorder-role"
  }
}

# AWS マネージドポリシー。Config Recorder に必要な Describe 権限が含まれている。
resource "aws_iam_role_policy_attachment" "config_recorder" {
  role       = aws_iam_role.config_recorder.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Config Recorder が S3 バケットへ書き込むために必要な権限。
resource "aws_iam_role_policy" "config_recorder_s3" {
  name = "${var.project_name}-config-recorder-s3-policy"
  role = aws_iam_role.config_recorder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Delivery"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketAcl",
        ]
        Resource = [
          aws_s3_bucket.config_logs.arn,
          "${aws_s3_bucket.config_logs.arn}/*",
        ]
      }
    ]
  })
}
