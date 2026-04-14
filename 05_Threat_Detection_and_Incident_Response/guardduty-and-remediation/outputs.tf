# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = aws_guardduty_detector.main.id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for remediation notifications"
  value       = aws_sns_topic.remediation_alerts.arn
}

output "threat_intel_bucket" {
  description = "S3 bucket name for custom threat intelligence lists"
  value       = aws_s3_bucket.threat_intel.bucket
}
