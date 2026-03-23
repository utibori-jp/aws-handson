# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "cross_account_role_arn" {
  description = "ARN of the cross-account role in the peer account"
  value       = aws_iam_role.cross_account.arn
}

# AssumeRole の動作確認用コマンド。
# 出力された ARN をそのままコピーして実行できる。
output "assume_role_command" {
  description = "Command to assume the cross-account role from the learner account"
  value       = "aws sts assume-role --role-arn ${aws_iam_role.cross_account.arn} --role-session-name cross-account-test --profile learner-admin"
}

output "secret_s3_uri" {
  description = "S3 URI of the secret file in the peer account"
  value       = "s3://${aws_s3_bucket.peer_demo.id}/secret.txt"
}

# ---
# 確認用情報
# ---

output "learner_account_id" {
  description = "Learner account ID (source)"
  value       = local.learner_account_id
}

output "peer_account_id" {
  description = "Peer account ID (target)"
  value       = local.peer_account_id
}
