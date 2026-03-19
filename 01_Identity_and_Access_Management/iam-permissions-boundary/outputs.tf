# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "developer_boundary_policy_arn" {
  description = "ARN of the permissions boundary policy"
  value       = aws_iam_policy.developer_boundary.arn
}
