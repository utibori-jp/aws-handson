# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.main.name
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.main.name
}

output "conformance_pack_name" {
  description = "Name of the Conformance Pack"
  value       = aws_config_conformance_pack.scs_checks.name
}

output "config_s3_bucket" {
  description = "S3 bucket receiving AWS Config logs"
  value       = aws_s3_bucket.config.bucket
}

# ---
# 操作確認用 CLI コマンド
# ---

output "cmd_check_compliance_summary" {
  description = "Command to check overall compliance summary for the Conformance Pack"
  value       = <<-EOT
    # Conformance Pack 全体の準拠状況サマリーを確認（apply から数分後に評価結果が揃う）
    aws configservice describe-conformance-pack-compliance \
      --conformance-pack-name "${aws_config_conformance_pack.scs_checks.name}" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'ConformancePackRuleComplianceList[*].{Rule: ConfigRuleNamesMap, Status: ComplianceType}' \
      --output table
  EOT
}

output "cmd_check_noncompliant_resources" {
  description = "Command to list non-compliant resources for a specific Config rule"
  value       = <<-EOT
    # 非準拠リソースの一覧を取得（ルール名は上記コマンドで確認する）
    aws configservice get-compliance-details-by-config-rule \
      --config-rule-name "iam-user-mfa-enabled" \
      --compliance-types NON_COMPLIANT \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'EvaluationResults[*].{Resource: EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId, Type: EvaluationResultIdentifier.EvaluationResultQualifier.ResourceType}'
  EOT
}

output "cmd_trigger_manual_evaluation" {
  description = "Command to trigger a manual Config rule re-evaluation"
  value       = <<-EOT
    # 特定ルールを即時再評価する（設定変更後に反映を早めたい場合）
    aws configservice start-config-rules-evaluation \
      --config-rule-names "s3-bucket-server-side-encryption-enabled" \
      --profile ${var.aws_profile} \
      --region ${var.region}
  EOT
}

output "cmd_get_config_rule_compliance" {
  description = "Command to check compliance of all Config rules in this account"
  value       = <<-EOT
    # アカウント全体のルール準拠状況（NON_COMPLIANT のみ表示）
    aws configservice describe-compliance-by-config-rule \
      --compliance-types NON_COMPLIANT \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'ComplianceByConfigRules[*].{Rule: ConfigRuleName, Status: Compliance.ComplianceType}' \
      --output table
  EOT
}
