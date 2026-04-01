# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

# ---
# AWS Config
# ---

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
# Security Hub
# ---

output "securityhub_hub_arn" {
  description = "ARN of the Security Hub"
  value       = aws_securityhub_account.main.id
}

output "fsbp_subscription_arn" {
  description = "ARN of the FSBP standards subscription"
  value       = aws_securityhub_standards_subscription.fsbp.id
}

output "cis_subscription_arn" {
  description = "ARN of the CIS 1.2.0 standards subscription"
  value       = aws_securityhub_standards_subscription.cis.id
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

output "cmd_get_security_score" {
  description = "Command to check Security Hub security score (FAILED controls)"
  value       = <<-EOT
    # FSBP スタンダードで FAILED になっているコントロールを確認する
    aws securityhub describe-standards-controls \
      --standards-subscription-arn "${aws_securityhub_standards_subscription.fsbp.id}" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'Controls[?ControlStatus==`FAILED`].{Title: Title, Status: ControlStatus, Severity: SeverityRating}' \
      --output table
  EOT
}

output "cmd_list_findings" {
  description = "Command to list HIGH/CRITICAL findings in Security Hub"
  value       = <<-EOT
    # HIGH / CRITICAL 重大度のフィンディングを確認する
    aws securityhub get-findings \
      --filters '{"SeverityLabel": [{"Value": "HIGH", "Comparison": "EQUALS"}, {"Value": "CRITICAL", "Comparison": "EQUALS"}], "WorkflowStatus": [{"Value": "NEW", "Comparison": "EQUALS"}]}' \
      --max-results 10 \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'Findings[*].{Title: Title, Severity: Severity.Label, ProductArn: ProductArn, Resource: Resources[0].Id}'
  EOT
}
