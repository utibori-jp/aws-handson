# =============================================================================
# outputs.tf
# apply 後に参照するリソース情報を出力する。
# =============================================================================

output "config_rule_arn" {
  description = "ARN of the Config Rule detecting public S3 buckets"
  value       = aws_config_config_rule.s3_public_access_prohibited.arn
}

output "config_logs_bucket_name" {
  description = "Name of the S3 bucket storing Config snapshots"
  value       = aws_s3_bucket.config_logs.bucket
}

output "config_remediation_role_arn" {
  description = "ARN of the IAM role used by SSM Automation for remediation"
  value       = aws_iam_role.config_remediation.arn
}
