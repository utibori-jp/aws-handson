# =============================================================================
# outputs.tf
# apply 後に参照するリソース情報を出力する。
# =============================================================================

output "flowlogs_bucket_name" {
  description = "Name of the S3 bucket storing VPC flow logs"
  value       = aws_s3_bucket.flowlogs.bucket
}

output "athena_database_name" {
  description = "Glue/Athena database name for VPC flow logs"
  value       = aws_glue_catalog_database.flowlogs.name
}

output "athena_workgroup_name" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.flowlogs.name
}

output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log resource"
  value       = aws_flow_log.main.id
}

output "instance_id" {
  description = "EC2 instance ID (use to filter flow logs by instance_id in Athena)"
  value       = aws_instance.main.id
}

output "public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.main.public_ip
}
