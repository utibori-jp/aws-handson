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
#
# 【確認ポイント】
# apply 後 5〜10 分で、CloudWatch Logs グループにログストリームが作成されることを確認する。
# ストリームが存在すれば CloudTrail → CloudWatch Logs の配信パイプラインが正常に機能している。
#
# aws logs describe-log-streams \
#   --log-group-name "/aws/cloudtrail/scs-handson-cis" \
#   --order-by LastEventTime \
#   --descending \
#   --limit 3 \
#   --profile learner-admin \
#   --region ap-northeast-1 \
#   --query 'logStreams[*].{stream: logStreamName, lastEvent: lastEventTimestamp}'
# =============================================================================

# ---
# CloudWatch Logs グループ
# ---

# CloudTrail ログの配信先ロググループ。
# retention_in_days で保持期間を設定する（無制限にすると CloudWatch Logs のコストが増える）。
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name = local.log_group_name
  # 検証用のためかなり短く設定
  retention_in_days = 7

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
# aws_iam_role_policyはインラインでロールに権限を埋め込めるため、そのロールでしか使わない独自権限ならコードも簡潔に記述できる。
# aws_iam_policyと、aws_iam_role_policy_attachmentを使うと、Policyを他のところでも使いまわせる。
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

# CloudTrail が S3 バケットへ書き込むために必要なバケットポリシーの定義。
# CloudTrail はユーザーの IAM ロールではなく、AWS サービス自身（サービスプリンシパル: cloudtrail.amazonaws.com）でアクセスする。
# そのため、バケットポリシーで cloudtrail.amazonaws.com を Principal として明示的に許可する必要がある。
#
# 【2つのステートメントが必要な理由】
# CloudTrail の仕様上、ログ書き込み（PutObject）の前に必ずバケット ACL の確認（GetBucketAcl）を行う。
# この事前確認が失敗すると Trail の作成自体が失敗するため、両方の許可が必須となる。
#
# 【Condition（AWS:SourceArn）による絞り込みの意味】
# Principal を cloudtrail.amazonaws.com とするだけでは「どの CloudTrail でも書き込める」状態になる。
# AWS:SourceArn で特定のアカウント・特定の証跡の ARN を指定することで、
# このバケットへのアクセスを「このアカウントのこの証跡だけ」に制限できる（Confused Deputy 攻撃の防止）。
data "aws_iam_policy_document" "cloudtrail_s3" {
  statement {
    # CloudTrail の仕様: PutObject の前に GetBucketAcl で書き込み権限を事前確認する。
    # このステートメントがないと Trail 作成時に "insufficient permissions" エラーになる。
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      # cloudtrail.amazonaws.com というサービスプリンシパル全体ではなく、
      # このアカウント・この証跡からのリクエストのみを許可する。
      values = ["arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    # AWSLogs/{account_id}/ 配下のみを対象にする（パス外への書き込みを防ぐ）。
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      # bucket-owner-full-control を要求することで、バケット所有者が常にログを読める状態を保証する。
      values = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"]
    }
  }
}

# 上記ポリシードキュメントを S3 バケットにアタッチする。
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket     = aws_s3_bucket.cloudtrail.id
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]

  policy = data.aws_iam_policy_document.cloudtrail_s3.json
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
