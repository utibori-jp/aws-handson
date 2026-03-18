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
