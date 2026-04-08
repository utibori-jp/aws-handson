# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = aws_guardduty_detector.main.id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for remediation notifications"
  value       = aws_sns_topic.remediation_alerts.arn
}

output "threat_intel_bucket" {
  description = "S3 bucket name for custom threat intelligence lists"
  value       = aws_s3_bucket.threat_intel.bucket
}

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_create_sample_findings_iam" {
  description = "Command to generate GuardDuty IAM sample findings (triggers remediate-iam-key Lambda)"
  value       = <<-EOT
    aws guardduty create-sample-findings \
      --detector-id "${aws_guardduty_detector.main.id}" \
      --finding-types "UnauthorizedAccess:IAMUser/MaliciousIPCaller" \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → finding_publishing_frequency = FIFTEEN_MINUTES のため 15 分以内に EventBridge へ発行される
    # → remediate-iam-key Lambda が呼び出され IAM キー無効化を試みる（サンプルはダミーユーザーのため not_found になる）
    # → SNS 通知は届かない（not_found パスでは送信しない）
  EOT
}

output "cmd_create_sample_findings_ec2" {
  description = "Command to generate GuardDuty EC2 sample findings (triggers isolate-ec2 Lambda)"
  value       = <<-EOT
    aws guardduty create-sample-findings \
      --detector-id "${aws_guardduty_detector.main.id}" \
      --finding-types "CryptoCurrency:EC2/BitcoinTool.B!DNS" \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → isolate-ec2 Lambda が呼び出されるが、サンプルのダミーインスタンス ID は存在しないため not_found になる
  EOT
}

output "cmd_test_kms_remediation" {
  description = "Commands to test CloudTrail-based KMS key deletion remediation"
  value       = <<-EOT
    # 1. テスト用 KMS キーを作成する（すでにあれば既存キーの ID を使う）
    KEY_ID=$(aws kms create-key \
      --description "test-key-for-guardduty-remediation" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'KeyMetadata.KeyId' --output text)
    echo "KeyId: $KEY_ID"

    # 2. 削除予約を実行する（EventBridge → Lambda が即時反応する）
    aws kms schedule-key-deletion \
      --key-id "$KEY_ID" \
      --pending-window-in-days 7 \
      --profile ${var.aws_profile} \
      --region ${var.region}

    # 3. Lambda ログで自動キャンセルを確認する
    aws logs tail "/aws/lambda/${var.project_name}-cancel-kms-deletion" \
      --follow \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → "CancelKeyDeletion succeeded" および "EnableKey succeeded" が記録されることを確認する
    # → SNS 通知メールが届くことを確認する（alert_email を設定した場合）
  EOT
}

output "cmd_test_sg_remediation" {
  description = "Commands to test CloudTrail-based SG open ingress remediation"
  value       = <<-EOT
    # 1. テスト用 SG を作成する（デフォルト VPC の ID を取得してから実行する）
    VPC_ID=$(aws ec2 describe-vpcs \
      --filters Name=isDefault,Values=true \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'Vpcs[0].VpcId' --output text)
    SG_ID=$(aws ec2 create-security-group \
      --group-name "test-sg-remediation" \
      --description "test sg for guardduty-and-remediation" \
      --vpc-id "$VPC_ID" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'GroupId' --output text)
    echo "SgId: $SG_ID"

    # 2. 全開放インバウンドルールを追加する（EventBridge → Lambda が即時反応する）
    aws ec2 authorize-security-group-ingress \
      --group-id "$SG_ID" \
      --protocol tcp --port 22 \
      --cidr 0.0.0.0/0 \
      --profile ${var.aws_profile} \
      --region ${var.region}

    # 3. Lambda ログで自動取り消しを確認する
    aws logs tail "/aws/lambda/${var.project_name}-revoke-sg-ingress" \
      --follow \
      --profile ${var.aws_profile} \
      --region ${var.region}
    # → "Revoked 1 dangerous rule(s)" が記録されることを確認する
  EOT
}

output "cmd_check_threat_intel" {
  description = "Command to check registered threat intel and trusted IP sets"
  value       = <<-EOT
    # ThreatIntelSet の確認
    aws guardduty list-threat-intel-sets \
      --detector-id "${aws_guardduty_detector.main.id}" \
      --profile ${var.aws_profile} \
      --region ${var.region}

    # IPSet（Trusted IP）の確認
    aws guardduty list-ip-sets \
      --detector-id "${aws_guardduty_detector.main.id}" \
      --profile ${var.aws_profile} \
      --region ${var.region}
  EOT
}
