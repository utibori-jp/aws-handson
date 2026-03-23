# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "deny_root_actions_policy_id" {
  description = "ID of the SCP that denies root user actions"
  value       = aws_organizations_policy.deny_root_actions.id
}

output "deny_root_actions_policy_arn" {
  description = "ARN of the SCP that denies root user actions"
  value       = aws_organizations_policy.deny_root_actions.arn
}

output "region_guardrail_policy_id" {
  description = "ID of the SCP that restricts regions to ap-northeast-1"
  value       = aws_organizations_policy.region_guardrail.id
}

output "region_guardrail_policy_arn" {
  description = "ARN of the SCP that restricts regions to ap-northeast-1"
  value       = aws_organizations_policy.region_guardrail.arn
}

output "target_ou_id" {
  description = "OU ID where SCPs are attached"
  value       = var.target_ou_id
}
