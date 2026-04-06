# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "security_lake_s3_bucket_arn" {
  description = "ARN of the S3 bucket created by Security Lake for log storage"
  value       = aws_securitylake_data_lake.main.s3_bucket_arn
}

output "kms_key_arn" {
  description = "ARN of the KMS CMK used for Security Lake encryption"
  value       = aws_kms_key.security_lake.arn
}

output "subscriber_role_arn" {
  description = "ARN of the IAM role for the query subscriber (use for Athena access)"
  value       = aws_securitylake_subscriber.query.role_arn
}
