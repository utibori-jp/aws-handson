# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC created for this module"
  value       = aws_vpc.main.id
}

output "vpc_endpoint_id" {
  description = "ID of the S3 Gateway VPC Endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_prefix_list_id" {
  description = "Prefix list ID of the S3 Gateway Endpoint (used in security group rules)"
  value       = aws_vpc_endpoint.s3.prefix_list_id
}

output "endpoint_test_bucket_name" {
  description = "Name of the S3 bucket for VPC Endpoint testing"
  value       = aws_s3_bucket.endpoint_test.bucket
}

output "endpoint_test_bucket_arn" {
  description = "ARN of the S3 bucket for VPC Endpoint testing"
  value       = aws_s3_bucket.endpoint_test.arn
}

output "test_instance_id" {
  description = "Instance ID of the test EC2 (use with SSM Session Manager)"
  value       = aws_instance.test.id
}
