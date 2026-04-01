# =============================================================================
# flowlogs.tf — vpc-flowlogs-athena
# VPC フローログを S3 に出力する設定。
#
# 【VPC フローログとは】
# VPC の ENI を通過するネットワークトラフィック（許可・拒否）を記録するサービス。
# ソース/デスティネーション IP、ポート、プロトコル、バイト数、許可/拒否 などが記録される。
# セキュリティグループや NACL のデバッグ、不審な通信の調査に使う（SCS 頻出）。
#
# 【出力先: S3 vs CloudWatch Logs】
# - S3: 大量ログの長期保管・Athena による SQL 分析に適する（本モジュールで採用）
# - CloudWatch Logs: リアルタイム検知・メトリクスフィルタとの連携に適する
#   （コスト高のため大量ログには不向き）
#
# 【カスタムフォーマット】
# デフォルトフォーマットに加え、vpc-id / subnet-id / az-id など拡張フィールドを追加。
# Athena でクエリする際に VPC・サブネット単位の絞り込みが可能になる。
#
# 【Security Lake との関係】
# VPC Flow Logs は Amazon Security Lake の自動ソースとしても取り込める。
# security-lake モジュールを apply すると、このモジュールとは別に Security Lake が
# VPC Flow Logs を OCSF 形式で正規化・集約する。両者は独立して共存できる。
# （このモジュール: カスタム Parquet で詳細分析、Security Lake: OCSF で横断分析）
# =============================================================================

# ---
# フローログ用 S3 バケット
# ---

resource "aws_s3_bucket" "flowlogs" {
  bucket        = "${var.project_name}-vpc-flowlogs"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-vpc-flowlogs"
  }
}

resource "aws_s3_bucket_versioning" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# VPC フローログサービスがバケットに書き込むためのバケットポリシー。
# フローログは delivery.logs.amazonaws.com サービスプリンシパルから書き込まれる。
resource "aws_s3_bucket_policy" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.flowlogs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.flowlogs.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# ---
# VPC フローログ
# ---

resource "aws_flow_log" "main" {
  vpc_id          = local.vpc_id
  traffic_type    = "ALL" # ACCEPT / REJECT / ALL。全トラフィックを記録する。
  iam_role_arn    = null  # S3 出力は IAM ロール不要（CloudWatch Logs 出力時のみ必要）。
  log_destination = aws_s3_bucket.flowlogs.arn

  # S3 出力を指定する。
  log_destination_type = "s3"

  # Parquet 形式で保存する。
  # デフォルトのテキスト形式より Athena のクエリが高速になりストレージコストも削減できる。
  destination_options {
    file_format        = "parquet"
    per_hour_partition = true # 時間ごとにパーティションを分けて Athena のスキャン量を削減する。
  }

  # カスタムフォーマット。デフォルトフィールド + 拡張フィールドを追加。
  # Athena テーブル定義と一致させる必要がある。
  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id}"

  tags = {
    Name = "${var.project_name}-vpc-flowlogs"
  }
}
