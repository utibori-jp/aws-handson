# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

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

output "cmd_get_security_score" {
  description = "Command to check Security Hub security score by standard"
  value       = <<-EOT
    # スタンダードごとのセキュリティスコアを確認する
    aws securityhub describe-standards-controls \
      --standards-subscription-arn "${aws_securityhub_standards_subscription.fsbp.id}" \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'Controls[?ControlStatus==`FAILED`].{Title: Title, Status: ControlStatus, Severity: SeverityRating}' \
      --output table
  EOT
}

output "cmd_list_findings" {
  description = "Command to list all FAILED findings (high severity)"
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

output "cmd_get_findings_summary" {
  description = "Command to get a summary of findings by severity"
  value       = <<-EOT
    # 重大度別のフィンディング件数を確認する
    for severity in CRITICAL HIGH MEDIUM LOW INFORMATIONAL; do
      count=$(aws securityhub get-findings \
        --filters "{\"SeverityLabel\": [{\"Value\": \"$severity\", \"Comparison\": \"EQUALS\"}]}" \
        --profile ${var.aws_profile} \
        --region ${var.region} \
        --query 'length(Findings)' \
        --output text 2>/dev/null || echo "0")
      echo "$severity: $count findings"
    done
  EOT
}

output "cmd_get_guardduty_findings" {
  description = "Command to get GuardDuty findings in Security Hub (ASFF format)"
  value       = <<-EOT
    # Security Hub 経由で GuardDuty フィンディングを ASFF 形式で取得する
    # guardduty-threat-detection モジュールのサンプルフィンディング生成後に実行する
    aws securityhub get-findings \
      --filters '{"ProductName": [{"Value": "GuardDuty", "Comparison": "EQUALS"}]}' \
      --max-results 5 \
      --profile ${var.aws_profile} \
      --region ${var.region} \
      --query 'Findings[*].{Type: Types[0], Severity: Severity.Label, Title: Title, Remediation: Remediation.Recommendation.Text}'
  EOT
}
