# =============================================================================
# config.tf — config-securityhub
# AWS Config の設定レコーダー・配信チャネルを有効化する。
#
# 【AWS Config とは】
# アカウント内のリソースの「設定状態」を継続的に記録し、
# 設定変更の履歴を追跡して「コンプライアンスルール」に照らし合わせて評価するサービス。
# GuardDuty（振る舞い検知）と対照的に、Config は「設定の静的評価」を担う（SCS 頻出の対比）。
#
# 【3リソースの依存順序】
# AWS Config を有効化するには以下の順序が必要（depends_on で明示する）：
#   1. aws_config_configuration_recorder — 「何を記録するか」の設定
#   2. aws_config_delivery_channel       — 「どこに配信するか」の設定
#   3. aws_config_configuration_recorder_status — レコーダーの有効化
#
# レコーダーステータスは配信チャネルが存在しないと有効化できないため、
# この順序を守らないと "InsufficientDeliveryPolicyException" エラーが発生する。
#
# 【⚠️ 課金について】
# Config は記録したリソースの設定変更 1 件ごとに課金される（無料枠あり）。
# 学習後は terraform destroy でレコーダーを停止することを推奨する。
# =============================================================================

# ---
# Config サービスロール
# ---

# Config が AWS リソースの設定を読み取り、S3 に配信するために必要な IAM ロール。
resource "aws_iam_role" "config" {
  name = "${var.project_name}-config-role"

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
    Name = "${var.project_name}-config-role"
  }
}

# AWS 管理ポリシーの AWSConfigRole をアタッチする。
# S3 への ConfigHistory/ConfigSnapshot の書き込み、SNS 通知、リソース読み取りに必要な権限が含まれる。
resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRole"
}

# ---
# S3 バケット（Config スナップショット・履歴の保管先）
# ---

resource "aws_s3_bucket" "config" {
  bucket        = "${var.project_name}-config-logs"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-config-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Config が S3 バケットへ書き込むために必要なバケットポリシー。
resource "aws_s3_bucket_policy" "config" {
  bucket     = aws_s3_bucket.config.id
  depends_on = [aws_s3_bucket_public_access_block.config]

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
        Resource = aws_s3_bucket.config.arn
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
        Resource = "${aws_s3_bucket.config.arn}/AWSLogs/${local.account_id}/Config/*"
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
# Step 1: 設定レコーダー
# ---

# 「何を記録するか」を定義するリソース。
# recording_group で記録対象のリソースタイプを指定する。
resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    # 全リソースタイプを記録する（Conformance Pack のルール評価に必要なリソースをカバーするため）。
    # コスト削減のため特定リソースに絞りたい場合は all_supported = false にして
    # resource_types リストに必要なものだけを列挙する。
    all_supported                 = true
    include_global_resource_types = true
  }
}

# ---
# Step 2: 配信チャネル
# ---

# 「どこに配信するか」を定義するリソース。
# レコーダーが先に存在する必要があるため depends_on を明示する。
resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-config-channel"
  s3_bucket_name = aws_s3_bucket.config.bucket

  depends_on = [
    aws_config_configuration_recorder.main,
    aws_s3_bucket_policy.config,
  ]
}

# ---
# Step 3: レコーダーの有効化
# ---

# レコーダーを「有効化」するリソース。
# 配信チャネルが存在しないと有効化できないため depends_on を明示する。
# この3ステップの順序が AWS Config セットアップのポイント（SCS 頻出）。
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}
