# =============================================================================
# ssm.tf
# Session Manager のデフォルト設定ドキュメント。
#
# "SSM-SessionManagerRunShell" という名前のドキュメントを作成すると、
# Session Manager がセッション開始時にこの設定を自動的に使用する。
# ログの S3 出力先と暗号化設定をここで一元管理する。
# =============================================================================

resource "aws_ssm_document" "session_manager_prefs" {
  name          = "SSM-SessionManagerRunShell"
  document_type = "Session"

  # schemaVersion "1.0" は Session ドキュメント専用のスキーマ。
  # s3BucketName を指定するだけでセッションログが自動的に S3 に書き込まれる。
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences - logs to S3 with KMS encryption"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName        = aws_s3_bucket.session_logs.id
      s3KeyPrefix         = local.account_id
      s3EncryptionEnabled = true
      # CloudWatch Logs への出力は今回は無効。S3 に集約する。
      cloudWatchLogGroupName      = ""
      cloudWatchEncryptionEnabled = false
    }
  })

  tags = {
    Name = "${var.project_name}-session-manager-prefs"
  }
}
