# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

# ---
# AWS Config
# ---

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.main.name
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.main.name
}

output "conformance_pack_name" {
  description = "Name of the Conformance Pack"
  value       = aws_config_conformance_pack.scs_checks.name
}

output "config_s3_bucket" {
  description = "S3 bucket receiving AWS Config logs"
  value       = aws_s3_bucket.config.bucket
}

# ---
# Security Hub（Learner アカウント・メンバー側）
# ---

output "securityhub_hub_arn" {
  description = "ARN of the Security Hub in the Learner account (member)"
  value       = aws_securityhub_account.main.id
}

output "fsbp_subscription_arn" {
  description = "ARN of the FSBP standards subscription in the Learner account"
  value       = aws_securityhub_standards_subscription.fsbp.id
}

output "cis_subscription_arn" {
  description = "ARN of the CIS 1.2.0 standards subscription in the Learner account"
  value       = aws_securityhub_standards_subscription.cis.id
}

# ---
# Security Hub（Peer アカウント・委任管理者側）
# ---

output "peer_securityhub_hub_arn" {
  description = "ARN of the Security Hub in the Peer account (delegated administrator)"
  value       = aws_securityhub_account.peer.id
}

output "peer_fsbp_subscription_arn" {
  description = "ARN of the FSBP standards subscription in the Peer account (delegated administrator)"
  value       = aws_securityhub_standards_subscription.peer_fsbp.id
}
