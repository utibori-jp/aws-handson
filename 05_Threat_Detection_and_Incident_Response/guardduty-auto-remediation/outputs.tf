# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = aws_guardduty_detector.main.id
}

output "lambda_iam_remediation_arn" {
  description = "ARN of the IAM key remediation Lambda"
  value       = aws_lambda_function.remediate_iam_key.arn
}

output "lambda_ec2_isolation_arn" {
  description = "ARN of the EC2 isolation Lambda"
  value       = aws_lambda_function.isolate_ec2.arn
}

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_create_sample_findings" {
  description = "Command to generate sample GuardDuty findings (triggers Lambda via EventBridge after ~15 min)"
  value       = <<-EOT
    aws guardduty create-sample-findings \
      --detector-id "${aws_guardduty_detector.main.id}" \
      --finding-types \
          "UnauthorizedAccess:IAMUser/MaliciousIPCaller" \
          "CryptoCurrency:EC2/BitcoinTool.B!DNS" \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → finding_publishing_frequency = FIFTEEN_MINUTES のため 15 分以内に EventBridge へ発行される
    # → 各 Lambda が呼び出され CloudWatch Logs にログが記録される
  EOT
}

output "cmd_check_iam_lambda_logs" {
  description = "Command to check IAM remediation Lambda execution logs"
  value       = <<-EOT
    aws logs tail "${aws_cloudwatch_log_group.remediate_iam_key.name}" \
      --follow \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → "SUCCESS: Disabled AccessKey" または "not found (sample finding)" が記録される
  EOT
}

output "cmd_check_ec2_lambda_logs" {
  description = "Command to check EC2 isolation Lambda execution logs"
  value       = <<-EOT
    aws logs tail "${aws_cloudwatch_log_group.isolate_ec2.name}" \
      --follow \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → "SUCCESS: Isolated instance" または "not found (sample finding)" が記録される
  EOT
}

output "cmd_check_eventbridge_invocations" {
  description = "Command to check EventBridge rule invocation metrics"
  value       = <<-EOT
    # IAM 修復ルールの呼び出し件数
    aws cloudwatch get-metric-statistics \
      --namespace AWS/Events \
      --metric-name Invocations \
      --dimensions Name=RuleName,Value="${aws_cloudwatch_event_rule.iam_remediation.name}" \
      --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
      --period 3600 \
      --statistics Sum \
      --profile ${var.aws_profile} \
      --region ${var.region}
  EOT
}
