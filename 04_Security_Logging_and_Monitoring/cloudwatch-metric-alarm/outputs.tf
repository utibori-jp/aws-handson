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
