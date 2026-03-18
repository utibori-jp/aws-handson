# =============================================================================
# outputs.tf
# apply 後に参照するリソース情報を出力する。
# =============================================================================

output "cancel_kms_deletion_lambda_arn" {
  description = "ARN of the Lambda function that cancels KMS key deletion"
  value       = aws_lambda_function.cancel_kms_deletion.arn
}

output "revoke_sg_ingress_lambda_arn" {
  description = "ARN of the Lambda function that revokes SG ingress rules"
  value       = aws_lambda_function.revoke_sg_ingress.arn
}

output "eventbridge_rule_arns" {
  description = "ARNs of the EventBridge rules triggering remediation"
  value = {
    kms_key_deletion    = aws_cloudwatch_event_rule.kms_key_deletion.arn
    sg_ingress_all_open = aws_cloudwatch_event_rule.sg_ingress_all_open.arn
  }
}
