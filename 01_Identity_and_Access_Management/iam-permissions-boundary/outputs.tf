# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "developer_boundary_policy_arn" {
  description = "ARN of the permissions boundary policy"
  value       = aws_iam_policy.developer_boundary.arn
}

# ---
# フォールバック（learner アカウント不使用時）用
# ---

output "developer_role_arn" {
  description = "ARN of the developer IAM role (fallback for AssumeRole testing without learner account)"
  value       = aws_iam_role.developer.arn
}

# AssumeRole の動作確認用 CLI コマンド（フォールバック時）。
output "assume_role_cli_command" {
  description = "CLI command to assume the developer role for fallback testing"
  value       = "aws sts assume-role --role-arn ${aws_iam_role.developer.arn} --role-session-name boundary-test"
}
