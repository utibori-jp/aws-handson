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

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_check_log_sources" {
  description = "Command to verify enabled log sources in Security Lake"
  value       = <<-EOT
    # 有効化されているログソースを確認する
    aws securitylake list-log-sources \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'sources[*].{Account: account, SourceName: sourceName, Status: sourceVersion}' \
      --output table
  EOT
}

output "cmd_check_data_lake_status" {
  description = "Command to check Security Lake data lake status"
  value       = <<-EOT
    # Security Lake の状態を確認する（INITIALIZED になるまで数分かかる）
    aws securitylake list-data-lakes \
      --regions ${var.region} \
      --profile ${var.aws_profile} \
      --query 'dataLakes[*].{Region: region, Status: createStatus, Bucket: s3BucketArn}' \
      --output table
  EOT
}

output "cmd_query_cloudtrail_ocsf" {
  description = "Sample Athena query to check CloudTrail events in OCSF format"
  value       = <<-EOT
    # Athena コンソールで以下のクエリを実行して OCSF 形式の CloudTrail ログを確認する。
    # データベース名は Amazon Security Lake が自動作成する（通常 "amazon_security_lake_glue_db_<region>"）。
    #
    # SELECT
    #   time,
    #   cloud.region,
    #   actor.user.name,
    #   api.operation,
    #   api.service.name,
    #   src_endpoint.ip
    # FROM amazon_security_lake_glue_db_ap_northeast_1.amazon_security_lake_table_ap_northeast_1_cloud_trail_mgmt_2_0
    # WHERE time_dt > current_timestamp - interval '1' hour
    # ORDER BY time DESC
    # LIMIT 20;
  EOT
}
