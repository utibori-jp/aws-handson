# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

# ---
# S3 バケット
# ---

output "bucket_name" {
  description = "Name of the Object Lock-enabled S3 bucket"
  value       = aws_s3_bucket.protected.bucket
}

output "bucket_arn" {
  description = "ARN of the Object Lock-enabled S3 bucket"
  value       = aws_s3_bucket.protected.arn
}

output "demo_object_key" {
  description = "S3 key of the demo object (protected by Object Lock)"
  value       = aws_s3_object.demo.key
}

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_get_object_version" {
  description = "Command to get the version ID of the demo object (needed for delete operations)"
  value       = <<-EOT
    aws s3api list-object-versions \
      --bucket "${aws_s3_bucket.protected.bucket}" \
      --prefix "demo/protected-file.txt" \
      --profile ${var.aws_profile}
  EOT
}

output "cmd_delete_object_without_bypass" {
  description = "Command to try deleting the protected object WITHOUT bypass (should return AccessDenied)"
  value       = <<-EOT
    # バージョン ID は cmd_get_object_version で確認してから置換する
    aws s3api delete-object \
      --bucket "${aws_s3_bucket.protected.bucket}" \
      --key "demo/protected-file.txt" \
      --version-id "<VERSION_ID>" \
      --profile ${var.aws_profile}
    # → AccessDenied: Object Lock による保護で削除が拒否される
  EOT
}

output "cmd_delete_object_with_bypass" {
  description = "Command to delete the protected object WITH bypass (requires s3:BypassGovernanceRetention permission)"
  value       = <<-EOT
    # --bypass-governance-retention フラグで Governance モードをバイパス
    # s3:BypassGovernanceRetention 権限が必要（IAM ポリシーで明示的に Allow が必要）
    aws s3api delete-object \
      --bucket "${aws_s3_bucket.protected.bucket}" \
      --key "demo/protected-file.txt" \
      --version-id "<VERSION_ID>" \
      --bypass-governance-retention \
      --profile ${var.aws_profile}
  EOT
}
