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
