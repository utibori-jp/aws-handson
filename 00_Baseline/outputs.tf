# =============================================================================
# outputs.tf
# 他のモジュールや手動確認で参照するリソース情報を出力する。
# terraform apply 後に terraform output で値を確認できる。
# =============================================================================

# ---
# VPC
# ---

output "vpc_id" {
  description = "ID of the baseline VPC"
  value       = aws_vpc.main.id
}

# 後続章でALBやEC2を配置する際に参照する。
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

# 後続章でECSタスクやRDSを配置する際に参照する。
output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.main.id
}

# ---
# CloudTrail
# ---

output "cloudtrail_bucket_name" {
  description = "Name of the S3 bucket collecting CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "cloudtrail_trail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.main.arn
}

# ---
# Organizations / IAM Identity Center
# ---

output "learner_account_id" {
  description = "AWS account ID of the learner member account"
  value       = aws_organizations_account.learner.id
}

output "learner_admin_permission_set_arn" {
  description = "ARN of the Admin permission set for the learner account"
  value       = aws_ssoadmin_permission_set.learner_admin.arn
}

output "learner_readonly_permission_set_arn" {
  description = "ARN of the ReadOnly permission set for the learner account"
  value       = aws_ssoadmin_permission_set.learner_readonly.arn
}
