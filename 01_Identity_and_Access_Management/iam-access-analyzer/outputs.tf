# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "analyzer_arn" {
  description = "ARN of the IAM Access Analyzer"
  value       = aws_accessanalyzer_analyzer.account.arn
}

output "analyzer_id" {
  description = "ID of the IAM Access Analyzer"
  value       = aws_accessanalyzer_analyzer.account.id
}

output "analyzer_test_bucket_name" {
  description = "Name of the S3 bucket for Access Analyzer testing"
  value       = aws_s3_bucket.analyzer_test.bucket
}

output "analyzer_test_bucket_arn" {
  description = "ARN of the S3 bucket for Access Analyzer testing"
  value       = aws_s3_bucket.analyzer_test.arn
}
