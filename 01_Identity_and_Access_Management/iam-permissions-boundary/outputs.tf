# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "developer_role_arn" {
  description = "ARN of the developer IAM role (with permissions boundary)"
  value       = aws_iam_role.developer.arn
}

output "developer_boundary_policy_arn" {
  description = "ARN of the permissions boundary policy"
  value       = aws_iam_policy.developer_boundary.arn
}

# AssumeRole の動作確認用 CLI コマンド。
# terraform output assume_role_cli_command を実行してコマンドをコピーする。
output "assume_role_cli_command" {
  description = "aws cli command to assume the developer role for testing"
  value       = "aws sts assume-role --role-arn ${aws_iam_role.developer.arn} --role-session-name boundary-test --profile terraform-sso"
}
