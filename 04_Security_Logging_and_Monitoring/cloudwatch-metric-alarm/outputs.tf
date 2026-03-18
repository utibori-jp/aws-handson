# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "cloudtrail_name" {
  description = "Name of the CloudTrail trail"
  value       = aws_cloudtrail.cis.name
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Logs group name receiving CloudTrail logs"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for CIS alarms"
  value       = aws_sns_topic.cis_alarms.arn
}

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_trigger_root_usage_alarm" {
  description = "How to trigger CIS 3.1 alarm (root usage) — do NOT use root in production"
  value       = <<-EOT
    # ルートアカウントでコンソールにログインし、任意の操作（例: S3 一覧表示）を行う。
    # → CloudTrail に userIdentity.type = "Root" のログが記録される。
    # → 5 分以内にメトリクスが増加し、アラームが ALARM 状態に遷移する。
    #
    # アラーム状態を CLI で確認：
    aws cloudwatch describe-alarms \
      --alarm-names "${var.project_name}-root-usage" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'MetricAlarms[0].{State: StateValue, Reason: StateReason}'
  EOT
}

output "cmd_trigger_sg_change_alarm" {
  description = "Command to trigger CIS 3.10 alarm (security group change)"
  value       = <<-EOT
    # デフォルト VPC でセキュリティグループを作成して削除する（リソースが残らない操作）。
    SG_ID=$(aws ec2 create-security-group \
      --group-name "cis-alarm-test-$(date +%s)" \
      --description "CIS alarm test" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'GroupId' --output text)
    echo "Created SG: $SG_ID"
    aws ec2 delete-security-group \
      --group-id "$SG_ID" \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → CloudWatch メトリクス SecurityGroupChangeCount が増加し、5 分以内にアラームが発火する。
  EOT
}

output "cmd_check_all_alarm_states" {
  description = "Command to check the state of all CIS alarms"
  value       = <<-EOT
    aws cloudwatch describe-alarms \
      --alarm-name-prefix "${var.project_name}-" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'MetricAlarms[*].{Name: AlarmName, State: StateValue}' \
      --output table
  EOT
}

output "cmd_check_log_delivery" {
  description = "Command to verify CloudTrail logs are flowing to CloudWatch Logs"
  value       = <<-EOT
    # ロググループにログストリームが作成されているか確認（Trail 開始から 5〜10 分後）
    aws logs describe-log-streams \
      --log-group-name "${aws_cloudwatch_log_group.cloudtrail.name}" \
      --order-by LastEventTime \
      --descending \
      --limit 3 \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'logStreams[*].{stream: logStreamName, lastEvent: lastEventTimestamp}'
  EOT
}
