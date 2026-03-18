# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = aws_guardduty_detector.main.id
}

output "guardduty_detector_arn" {
  description = "ARN of the GuardDuty detector"
  value       = aws_guardduty_detector.main.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for GuardDuty alerts"
  value       = aws_sns_topic.guardduty_alerts.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for GuardDuty findings"
  value       = aws_cloudwatch_event_rule.guardduty_findings.arn
}

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_create_sample_findings" {
  description = "Command to generate sample GuardDuty findings for testing"
  value       = <<-EOT
    # サンプルフィンディングを生成する（全フィンディングタイプのサンプルが作成される）
    aws guardduty create-sample-findings \
      --detector-id "${aws_guardduty_detector.main.id}" \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → 15 分以内に EventBridge → SNS と転送される（finding_publishing_frequency = FIFTEEN_MINUTES）
    # → SNS メトリクス（NumberOfMessagesPublished）で確認できる
  EOT
}

output "cmd_list_findings" {
  description = "Command to list current GuardDuty findings"
  value       = <<-EOT
    # フィンディング ID 一覧を取得
    aws guardduty list-findings \
      --detector-id "${aws_guardduty_detector.main.id}" \
      --profile ${var.aws_profile} \
      --region ${var.region}
  EOT
}

output "cmd_get_finding_detail" {
  description = "Command to get finding details (replace FINDING_ID with actual ID)"
  value       = <<-EOT
    # フィンディングの詳細を取得（severity / type / region / accountId / service.action を確認）
    aws guardduty get-findings \
      --detector-id "${aws_guardduty_detector.main.id}" \
      --finding-ids "<FINDING_ID>" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      | jq '.Findings[0] | {type: .Type, severity: .Severity, title: .Title}'
  EOT
}

output "cmd_check_sns_metrics" {
  description = "Command to check SNS publish metrics (verify EventBridge → SNS is working)"
  value       = <<-EOT
    # SNS への転送件数を確認（サンプルフィンディング生成から 15 分後に増加する）
    aws cloudwatch get-metric-statistics \
      --namespace AWS/SNS \
      --metric-name NumberOfMessagesPublished \
      --dimensions Name=TopicName,Value="${aws_sns_topic.guardduty_alerts.name}" \
      --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
      --period 3600 \
      --statistics Sum \
      --profile ${var.aws_profile} \
      --region ${var.region}
  EOT
}
