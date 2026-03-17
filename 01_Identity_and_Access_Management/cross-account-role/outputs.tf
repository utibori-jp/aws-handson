# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

# ---
# ターゲットアカウント（信頼ポリシー側）
# ---

output "cross_account_role_arn" {
  description = "ARN of the cross-account role in the target account"
  value       = aws_iam_role.cross_account.arn
}

# ---
# ソースアカウント（AssumeRole 側）
# ---

output "caller_user_arn" {
  description = "ARN of the IAM user in the source account that can assume the cross-account role"
  value       = aws_iam_user.cross_account_caller.arn
}

output "assume_role_policy_arn" {
  description = "ARN of the policy that allows assuming the cross-account role"
  value       = aws_iam_policy.assume_cross_account.arn
}

# AssumeRole の動作確認用コマンド。
output "assume_role_cli_command" {
  description = "aws cli command to assume the cross-account role for testing"
  value       = "aws sts assume-role --role-arn ${aws_iam_role.cross_account.arn} --role-session-name cross-account-test --profile source-sso"
}

# ---
# 確認用情報
# ---

output "source_account_id" {
  description = "Source account ID"
  value       = local.source_account_id
}

output "target_account_id" {
  description = "Target account ID"
  value       = local.target_account_id
}
