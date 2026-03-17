# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

# ---
# KMS CMK
# ---

output "kms_key_arn" {
  description = "ARN of the CMK"
  value       = aws_kms_key.s3_cmk.arn
}

output "kms_key_id" {
  description = "Key ID of the CMK"
  value       = aws_kms_key.s3_cmk.key_id
}

output "kms_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = aws_kms_alias.s3_cmk.arn
}

output "kms_alias_name" {
  description = "Name of the KMS key alias"
  value       = aws_kms_alias.s3_cmk.name
}

# ---
# S3 バケット
# ---

output "bucket_name" {
  description = "Name of the SSE-KMS encrypted S3 bucket"
  value       = aws_s3_bucket.encrypted.bucket
}

output "bucket_arn" {
  description = "ARN of the SSE-KMS encrypted S3 bucket"
  value       = aws_s3_bucket.encrypted.arn
}

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_put_object" {
  description = "Command to upload a file to the encrypted bucket (should succeed with CMK encryption)"
  value       = <<-EOT
    echo "test content" > /tmp/test.txt
    aws s3 cp /tmp/test.txt s3://${aws_s3_bucket.encrypted.bucket}/test.txt \
      --profile ${var.aws_profile}
    # → 成功すると SSE-KMS（CMK）で暗号化される
  EOT
}

output "cmd_check_encryption" {
  description = "Command to verify the object is encrypted with the CMK"
  value       = <<-EOT
    aws s3api head-object \
      --bucket "${aws_s3_bucket.encrypted.bucket}" \
      --key "test.txt" \
      --profile ${var.aws_profile} \
      --query '{SSEAlgorithm: ServerSideEncryption, KMSKeyId: SSEKMSKeyId}'
    # → SSEAlgorithm: "aws:kms", KMSKeyId: "<CMK ARN>" が返ることを確認
  EOT
}

output "cmd_put_object_with_wrong_key" {
  description = "Command to try uploading with SSE-S3 (should be denied by bucket policy)"
  value       = <<-EOT
    echo "test content" > /tmp/test.txt
    aws s3api put-object \
      --bucket "${aws_s3_bucket.encrypted.bucket}" \
      --key "test-sse-s3.txt" \
      --body /tmp/test.txt \
      --server-side-encryption AES256 \
      --profile ${var.aws_profile}
    # → AccessDenied: バケットポリシーの DenyNonCMKEncryption が適用される
  EOT
}

output "cmd_cancel_key_deletion" {
  description = "Command to cancel CMK deletion after 'terraform destroy' (available within deletion_window_in_days=7)"
  value       = <<-EOT
    # terraform destroy 後、7 日以内であればキー削除をキャンセルできる。
    # キー ID は上記の kms_key_id output または AWS コンソールで確認する。
    aws kms cancel-key-deletion \
      --key-id "${aws_kms_key.s3_cmk.key_id}" \
      --profile ${var.aws_profile}
    # キャンセル後、キーを再有効化する（destroy 後は Disabled 状態）
    aws kms enable-key \
      --key-id "${aws_kms_key.s3_cmk.key_id}" \
      --profile ${var.aws_profile}
  EOT
}
