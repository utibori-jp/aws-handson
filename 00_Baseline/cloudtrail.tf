# =============================================================================
# cloudtrail.tf — 00_Baseline
# 管理アカウントにローカル証跡を作成し、API コールログを S3 バケットへ保管する。
#
# 【CloudTrail とは】
# AWS アカウント内の API コールを記録するサービス。
# 「誰が・いつ・何を操作したか」を追跡でき、セキュリティ調査・コンプライアンス対応の基盤となる。
# SCS頻出：「CloudTrail を有効化してログを S3 に集約する」
#
# 【確認ポイント】
# apply 後、以下で証跡が有効になっていることを確認する。
#
#   aws cloudtrail describe-trails --profile terraform-sso
#   aws cloudtrail get-trail-status \
#     --name <trail-name> \
#     --profile terraform-sso
# =============================================================================

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

# ログの保持期間を管理するライフサイクルポリシー。
# ストレージコストを抑えつつ、監査要件に応じた保管期間を設定する。
# 標準ストレージ → Glacier Instant Retrieval → 削除 の 3 段階で自動的に移行する。
#
# Glacier Instant Retrieval を選ぶ理由:
#   CloudTrail ログはインシデント発生時に即座に参照する必要がある。
#   Glacier Archive（旧 Glacier）は取得に 3〜5時間 かかるため、
#   インシデント対応には不向き。Glacier IR はミリ秒取得でありながら
#   Standard の約 68% コスト削減が可能。SCS 試験では「取得速度 vs コスト」の
#   トレードオフとして頻出。
#
# SCS 的観点: 保持期間はコンプライアンス要件（PCI DSS: 1年、HIPAA: 6年など）に合わせること。
# このハンズオンでは学習目的で短めに設定している。
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cloudtrail-log-lifecycle"
    status = "Enabled"

    # 30日後に Glacier Instant Retrieval へ移行。
    # 直近 30 日はアクセス頻度が高い（インシデント調査など）ため Standard に置く。
    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    # Glacier IR 移行から 90 日後（合計 120 日）に削除。
    # 本番では規制要件に合わせて延長すること（例: 7年保管が必要な場合は2555日）。
    expiration {
      days = 120
    }

    # バージョニング有効時、非現行バージョンも 30 日で削除。
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    # 中断されたマルチパートアップロードを 7 日後に自動削除。
    # 放置するとストレージ料金が発生し続けるため、明示的にクリーンアップする。
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# CloudTrailがバケットへ書き込むために必要なバケットポリシー。
# AWS:SourceArn 条件で自分の証跡のみに限定し、Confused Deputy 攻撃を防ぐ。
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ACL 確認権限。
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
        # ログ書き込み権限。
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            # bucket-owner-full-control はログの所有権をバケット所有者に移譲するための設定。
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

# 管理アカウントのローカル証跡。
resource "aws_cloudtrail" "main" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  # IAMやRoute53などグローバルサービスのAPIコールも記録する。
  include_global_service_events = true

  # 全リージョンのイベントを1つの証跡で収集する。
  is_multi_region_trail = true

  # ダイジェストファイルを使ってログが改ざんされていないかを検証できる（SCS頻出）。
  enable_log_file_validation = true

  # バケットポリシーが先に存在しないとCloudTrailの作成が失敗するため、明示的に依存関係を宣言する。
  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = {
    Name = local.trail_name
  }
}
