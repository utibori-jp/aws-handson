# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "macie_account_status" {
  description = "Status of the Macie account"
  value       = aws_macie2_account.main.status
}

output "classification_job_id" {
  description = "ID of the Macie classification job"
  value       = aws_macie2_classification_job.scan.id
}

output "test_bucket_name" {
  description = "Name of the S3 bucket containing dummy PII test data"
  value       = aws_s3_bucket.macie_test.bucket
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for Macie alerts"
  value       = aws_sns_topic.macie_alerts.arn
}

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_check_job_status" {
  description = "Command to check classification job status (wait for COMPLETE)"
  value       = <<-EOT
    aws macie2 describe-classification-job \
      --job-id "${aws_macie2_classification_job.scan.id}" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query '{Status: jobStatus, Statistics: statistics}'
    # → jobStatus が "COMPLETE" になるまで数分〜十数分かかる
    # → statistics.approximateNumberOfObjectsToProcess でスキャン対象オブジェクト数を確認
  EOT
}

output "cmd_list_findings" {
  description = "Command to list Macie findings (run after job is COMPLETE)"
  value       = <<-EOT
    aws macie2 list-findings \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'findingIds'
    # → ジョブ完了後にフィンディング ID が表示される（PII 検出があれば）
  EOT
}

output "cmd_get_finding_detail" {
  description = "Command to get finding details including detected data types and S3 object info"
  value       = <<-EOT
    # フィンディング ID は cmd_list_findings で取得する
    aws macie2 get-findings \
      --finding-ids "<FINDING_ID>" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'findings[0].{
        Type: type,
        Severity: severity.description,
        S3Object: resourcesAffected.s3Object.key,
        DataIdentifiers: classificationDetails.result.sensitiveData[*].category
      }'
    # → 確認ポイント：
    #   - type: SensitiveData:S3Object/Personal（PII 検出の場合）
    #   - S3Object: customer-data/test-customers.csv
    #   - DataIdentifiers: ["FINANCIAL_INFORMATION", "PERSONAL_HEALTH_INFORMATION"] など
  EOT
}

output "cmd_check_sns_delivery" {
  description = "Command to verify Macie finding was forwarded to SNS via EventBridge"
  value       = <<-EOT
    aws cloudwatch get-metric-statistics \
      --namespace AWS/SNS \
      --metric-name NumberOfMessagesPublished \
      --dimensions Name=TopicName,Value="${aws_sns_topic.macie_alerts.name}" \
      --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
      --period 3600 \
      --statistics Sum \
      --profile ${var.aws_profile} \
      --region ${var.region}
  EOT
}
