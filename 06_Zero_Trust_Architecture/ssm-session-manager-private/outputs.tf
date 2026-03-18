# =============================================================================
# outputs.tf
# 他のモジュール（verified-access など）から参照する値を出力する。
# =============================================================================

output "instance_id" {
  description = "ID of the EC2 instance. Use with: aws ssm start-session --target <instance_id>"
  value       = aws_instance.main.id
}

# Module 3 (verified-access) で network-interface エンドポイントのターゲットとして使う。
output "primary_network_interface_id" {
  description = "Primary ENI ID of the EC2 instance. Used as the backend target for Verified Access."
  value       = aws_instance.main.primary_network_interface_id
}

output "session_log_bucket_name" {
  description = "Name of the S3 bucket storing SSM Session Manager logs"
  value       = aws_s3_bucket.session_logs.id
}

output "session_log_bucket_arn" {
  description = "ARN of the S3 bucket storing SSM Session Manager logs"
  value       = aws_s3_bucket.session_logs.arn
}
