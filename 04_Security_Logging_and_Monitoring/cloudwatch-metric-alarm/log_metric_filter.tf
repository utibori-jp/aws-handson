# =============================================================================
# log_metric_filter.tf — cloudwatch-metric-alarm
# CIS AWS Foundations Benchmark 準拠のメトリクスフィルターを定義する。
#
# 【メトリクスフィルターとは】
# CloudWatch Logs のログデータから特定のパターン（CloudTrail イベント）を検出し、
# カスタムメトリクスのカウントを増加させる仕組み。
# このメトリクスに対してアラームを設定することで、特定操作の検知 → 通知が実現できる。
#
# 【CIS AWS Foundations Benchmark】
# AWS アカウントのセキュリティ設定を評価するためのベストプラクティス集。
# SCS 試験でよく参照される基準の1つ（他に NIST CSF / PCI DSS など）。
# =============================================================================

# ---
# CIS 3.1: ルートアカウントの使用を検知
# ---

# ルートアカウントでの操作はいかなる場合も避けるべき（SCS / CIS 頻出）。
# 緊急時以外にルートを使用した場合、即時通知できる体制が重要。
resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  name           = "${var.project_name}-root-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  # ルートアカウントによる操作（サービスイベントを除く）を検知する。
  pattern = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name          = "RootUsageCount"
    namespace     = "${var.project_name}/CISAlarms"
    value         = "1"
    default_value = "0"
  }
}

# ---
# CIS 3.2: MFA なしのコンソールログインを検知
# ---

# IAM ユーザーが MFA なしでマネジメントコンソールにログインした場合を検知する。
# MFA の強制は IAM ポリシー（03章）で実施するが、漏れを検知するバックストップとして機能する。
resource "aws_cloudwatch_log_metric_filter" "console_signin_without_mfa" {
  name           = "${var.project_name}-console-signin-no-mfa"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  # ConsoleLogin イベントで MFA なし・IAM ユーザー・成功のみを検知する。
  # AssumeRoleWithSAML（SSO）などの MFA 不要なログインは除外している。
  pattern = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"

  metric_transformation {
    name          = "ConsoleSigninWithoutMFACount"
    namespace     = "${var.project_name}/CISAlarms"
    value         = "1"
    default_value = "0"
  }
}

# ---
# CIS 3.7: 無認可の API コールを検知
# ---

# AccessDenied / UnauthorizedAccess エラーの急増は、
# 攻撃者が権限を探索している（偵察）サインである可能性がある。
resource "aws_cloudwatch_log_metric_filter" "unauthorized_api_calls" {
  name           = "${var.project_name}-unauthorized-api-calls"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = "{ ($.errorCode = \"AccessDenied\") || ($.errorCode = \"UnauthorizedAccess\") || ($.errorCode = \"*UnauthorizedOperation\") }"

  metric_transformation {
    name          = "UnauthorizedAPICallCount"
    namespace     = "${var.project_name}/CISAlarms"
    value         = "1"
    default_value = "0"
  }
}

# ---
# CIS 3.10: セキュリティグループの変更を検知
# ---

# セキュリティグループへのルール追加（特にインバウンド開放）は、
# 意図しないネットワークアクセスを生む可能性がある。変更の即時検知が重要。
resource "aws_cloudwatch_log_metric_filter" "security_group_changes" {
  name           = "${var.project_name}-sg-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = "{ ($.eventName = \"AuthorizeSecurityGroupIngress\") || ($.eventName = \"AuthorizeSecurityGroupEgress\") || ($.eventName = \"RevokeSecurityGroupIngress\") || ($.eventName = \"RevokeSecurityGroupEgress\") || ($.eventName = \"CreateSecurityGroup\") || ($.eventName = \"DeleteSecurityGroup\") }"

  metric_transformation {
    name          = "SecurityGroupChangeCount"
    namespace     = "${var.project_name}/CISAlarms"
    value         = "1"
    default_value = "0"
  }
}

# ---
# CIS 3.8: S3 バケットポリシーの変更を検知
# ---

# S3 バケットポリシーの変更は、機密データの意図しない公開につながるリスクがある（SCS 頻出）。
resource "aws_cloudwatch_log_metric_filter" "s3_bucket_policy_changes" {
  name           = "${var.project_name}-s3-policy-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = "{ ($.eventSource = \"s3.amazonaws.com\") && (($.eventName = \"PutBucketAcl\") || ($.eventName = \"PutBucketPolicy\") || ($.eventName = \"PutBucketCors\") || ($.eventName = \"PutBucketLifecycle\") || ($.eventName = \"DeleteBucketPolicy\") || ($.eventName = \"DeleteBucketCors\") || ($.eventName = \"DeleteBucketLifecycle\")) }"

  metric_transformation {
    name          = "S3BucketPolicyChangeCount"
    namespace     = "${var.project_name}/CISAlarms"
    value         = "1"
    default_value = "0"
  }
}
