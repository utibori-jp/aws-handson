# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

# ---
# KMS CMK（管理アカウント）
# ---

output "kms_key_arn" {
  description = "ARN of the CMK"
  value       = aws_kms_key.s3_cmk.arn
}

output "kms_key_id" {
  description = "Key ID of the CMK"
  value       = aws_kms_key.s3_cmk.key_id
}

output "kms_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = aws_kms_alias.s3_cmk.arn
}

output "kms_alias_name" {
  description = "Name of the KMS key alias"
  value       = aws_kms_alias.s3_cmk.name
}

# ---
# S3 バケット（Learner アカウント）
# ---

output "bucket_name" {
  description = "Name of the SSE-KMS encrypted S3 bucket (in Learner account)"
  value       = aws_s3_bucket.encrypted.bucket
}

output "bucket_arn" {
  description = "ARN of the SSE-KMS encrypted S3 bucket (in Learner account)"
  value       = aws_s3_bucket.encrypted.arn
}
