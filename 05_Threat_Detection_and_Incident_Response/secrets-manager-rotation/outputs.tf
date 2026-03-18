# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.app_credential.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.app_credential.name
}

output "kms_key_arn" {
  description = "ARN of the CMK used to encrypt the secret"
  value       = aws_kms_key.secrets_cmk.arn
}

output "rotation_lambda_arn" {
  description = "ARN of the rotation Lambda function"
  value       = aws_lambda_function.rotate_secret.arn
}

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_check_rotation_status" {
  description = "Command to verify rotation is enabled and check last rotation time"
  value       = <<-EOT
    aws secretsmanager describe-secret \
      --secret-id "${aws_secretsmanager_secret.app_credential.name}" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query '{RotationEnabled: RotationEnabled, LastRotatedDate: LastRotatedDate, NextRotationDate: NextRotationDate}'
    # → RotationEnabled: true, LastRotatedDate に apply 直後の時刻が入っていることを確認
  EOT
}

output "cmd_list_secret_versions" {
  description = "Command to list secret versions and stages (AWSCURRENT / AWSPREVIOUS)"
  value       = <<-EOT
    aws secretsmanager list-secret-version-ids \
      --secret-id "${aws_secretsmanager_secret.app_credential.name}" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'Versions[*].{VersionId: VersionId, Stages: VersionStages}'
    # → AWSCURRENT（ローテーション後）と AWSPREVIOUS（初期値）の2バージョンが存在することを確認
  EOT
}

output "cmd_get_current_secret" {
  description = "Command to get the current secret value (post-rotation password)"
  value       = <<-EOT
    aws secretsmanager get-secret-value \
      --secret-id "${aws_secretsmanager_secret.app_credential.name}" \
      --version-stage AWSCURRENT \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'SecretString'
    # → ローテーション後の新しいパスワードが含まれていることを確認
  EOT
}

output "cmd_get_previous_secret" {
  description = "Command to get the previous secret value (pre-rotation password = initial value)"
  value       = <<-EOT
    aws secretsmanager get-secret-value \
      --secret-id "${aws_secretsmanager_secret.app_credential.name}" \
      --version-stage AWSPREVIOUS \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'SecretString'
    # → 初期パスワード "initial-password-change-me" が残っていることを確認
    # → AWSCURRENT と AWSPREVIOUS でパスワードが異なることがローテーション成功の証拠
  EOT
}

output "cmd_check_rotation_lambda_logs" {
  description = "Command to view rotation Lambda logs (verify all 4 phases executed)"
  value       = <<-EOT
    aws logs tail "/aws/lambda/${var.project_name}-rotate-secret" \
      --follow \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → 以下の 4 フェーズのログが順番に記録されていることを確認：
    #   1. "createSecret: Created AWSPENDING version..."
    #   2. "setSecret: [STUB] Would update credentials..."
    #   3. "testSecret: [STUB] JSON structure check passed..."  ← スタブのため実接続なし
    #   4. "finishSecret: Promoted version ... to AWSCURRENT"
  EOT
}

output "cmd_cancel_kms_deletion" {
  description = "Command to cancel CMK deletion after terraform destroy (within 7 days)"
  value       = <<-EOT
    aws kms cancel-key-deletion \
      --key-id "${aws_kms_key.secrets_cmk.key_id}" \
      --profile ${var.aws_profile}
    aws kms enable-key \
      --key-id "${aws_kms_key.secrets_cmk.key_id}" \
      --profile ${var.aws_profile}
  EOT
}
