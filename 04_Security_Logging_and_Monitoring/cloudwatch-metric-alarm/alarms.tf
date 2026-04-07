# =============================================================================
# alarms.tf — cloudwatch-metric-alarm
# CIS ベンチマーク準拠のメトリクスアラームを定義する。
# log_metric_filter.tf で定義したカスタムメトリクスに対してアラームを設定する。
#
# 【アラームの仕組み】
# メトリクスが threshold を超えると ALARM 状態に遷移し、SNS に通知を送信する。
# - OK → ALARM: 1 件でも検知したら発火（threshold = 1, period = 300 秒）
# - ALARM → OK: 評価期間内に検知がなければ自動的に解除される
#
# 【評価期間について】
# evaluation_periods = 1, period = 300（5 分）は
# 「5 分間に 1 件以上発生したらアラーム」という設定。
# 本番環境でノイズが多い場合は evaluation_periods を増やして感度を下げる。
#
# 【確認ポイント】
# 全アラームが OK 状態（データなし = notBreaching）になっていることを確認する。
#
# aws cloudwatch describe-alarms \
#   --alarm-name-prefix "scs-handson-" \
#   --profile learner-admin \
#   --region ap-northeast-1 \
#   --query 'MetricAlarms[*].{Name: AlarmName, State: StateValue}' \
#   --output table
#
# CIS 3.10（SG 変更）アラームの発火テスト。
# セキュリティグループを作成・即削除することでイベントを発生させる（リソースは残らない）。
#
# SG_ID=$(aws ec2 create-security-group \
#   --group-name "cis-alarm-test-$(date +%s)" \
#   --description "CIS alarm test" \
#   --profile learner-admin \
#   --region ap-northeast-1 \
#   --query 'GroupId' --output text)
# aws ec2 delete-security-group \
#   --group-id "$SG_ID" \
#   --profile learner-admin \
#   --region ap-northeast-1
# → 約 5 分後に scs-handson-sg-changes が ALARM に遷移し、SNS 通知が届く。
# =============================================================================

# メトリクスフィルター方式（このファイル）と EventBridge 方式（eventbridge.tf）は
# 検知対象が完全には一致しない。これは設計上意図的なもので、両方式がそれぞれ独立して
# 同一の SNS トピックへ直接 Publish する構成になっている。
# ルートユーザー検知のように両方式でカバーしているものは多重検知になるが、
# 「5 分遅延でも確実な CIS 準拠」と「秒単位のリアルタイム検知」を同時に実現するための意図的な冗長性。

# ---
# CIS 3.1: ルートアカウント使用アラーム
# ---

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "${var.project_name}-root-usage"
  alarm_description   = "CIS 3.1 - Root account usage detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RootUsageCount"
  namespace           = "${var.project_name}/CISAlarms"
  period              = 300
  statistic           = "Sum"
  threshold           = 1

  # メトリクスデータがない期間をどう扱うか。
  # notBreaching: データなしは「正常」として扱う。
  # ログが流れていない初期状態でアラームが誤発火しないようにする。
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.cis_alarms.arn]
  ok_actions    = [aws_sns_topic.cis_alarms.arn]

  tags = {
    Name = "${var.project_name}-root-usage"
  }
}

# ---
# CIS 3.2: MFA なしコンソールログインアラーム
# ---

resource "aws_cloudwatch_metric_alarm" "console_signin_without_mfa" {
  alarm_name          = "${var.project_name}-console-signin-no-mfa"
  alarm_description   = "CIS 3.2 - Console sign-in without MFA detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ConsoleSigninWithoutMFACount"
  namespace           = "${var.project_name}/CISAlarms"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cis_alarms.arn]
  ok_actions    = [aws_sns_topic.cis_alarms.arn]

  tags = {
    Name = "${var.project_name}-console-signin-no-mfa"
  }
}

# ---
# CIS 3.7: 無認可 API コールアラーム
# ---

# 頻繁な AccessDenied は攻撃者の権限探索の可能性がある。
# ただし正常な開発フローでも発生しうるため、threshold を 10 に設定してノイズを抑制する。
resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  alarm_name          = "${var.project_name}-unauthorized-api-calls"
  alarm_description   = "CIS 3.7 - High rate of unauthorized API calls detected (possible reconnaissance)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedAPICallCount"
  namespace           = "${var.project_name}/CISAlarms"
  period              = 300
  statistic           = "Sum"

  # 5 分間に 10 件以上の AccessDenied でアラーム。
  # ハンズオンでは 1 に下げて試すと発火を確認しやすい。
  threshold          = 10
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.cis_alarms.arn]
  ok_actions    = [aws_sns_topic.cis_alarms.arn]

  tags = {
    Name = "${var.project_name}-unauthorized-api-calls"
  }
}

# ---
# CIS 3.10: セキュリティグループ変更アラーム
# ---

resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  alarm_name          = "${var.project_name}-sg-changes"
  alarm_description   = "CIS 3.10 - Security group change detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "SecurityGroupChangeCount"
  namespace           = "${var.project_name}/CISAlarms"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cis_alarms.arn]
  ok_actions    = [aws_sns_topic.cis_alarms.arn]

  tags = {
    Name = "${var.project_name}-sg-changes"
  }
}

# ---
# CIS 3.8: S3 バケットポリシー変更アラーム
# ---

resource "aws_cloudwatch_metric_alarm" "s3_bucket_policy_changes" {
  alarm_name          = "${var.project_name}-s3-policy-changes"
  alarm_description   = "CIS 3.8 - S3 bucket policy change detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "S3BucketPolicyChangeCount"
  namespace           = "${var.project_name}/CISAlarms"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.cis_alarms.arn]
  ok_actions    = [aws_sns_topic.cis_alarms.arn]

  tags = {
    Name = "${var.project_name}-s3-policy-changes"
  }
}
