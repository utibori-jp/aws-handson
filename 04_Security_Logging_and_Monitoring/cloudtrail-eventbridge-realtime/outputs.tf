# =============================================================================
# outputs.tf
# apply 後に参照するリソース情報を出力する。
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving CloudTrail real-time alerts"
  value       = aws_sns_topic.cloudtrail_alerts.arn
}

output "eventbridge_rule_arns" {
  description = "ARNs of the EventBridge rules created for dangerous API detection"
  value = {
    kms_key_deletion     = aws_cloudwatch_event_rule.kms_key_deletion.arn
    sg_ingress_all_open  = aws_cloudwatch_event_rule.sg_ingress_all_open.arn
    cloudtrail_changes   = aws_cloudwatch_event_rule.cloudtrail_changes.arn
    root_user_activity   = aws_cloudwatch_event_rule.root_user_activity.arn
    iam_user_key_creation = aws_cloudwatch_event_rule.iam_user_key_creation.arn
  }
}
