# =============================================================================
# outputs.tf
# ハンズオン検証で使う URL と ARN を出力する。
# =============================================================================

output "api_invoke_url" {
  description = "Invoke URL for GET /hello. Requires SigV4 signed request."
  value       = "${aws_api_gateway_stage.v1.invoke_url}/hello"
}

output "api_endpoint" {
  description = "Base URL of the API Gateway stage"
  value       = aws_api_gateway_stage.v1.invoke_url
}

# IAM ポリシーの Resource フィールドに指定する ARN。
# execute-api:Invoke を許可するポリシーを作る際にこの値を使う。
output "api_execution_arn" {
  description = "Execution ARN for use in IAM policy Resource field. e.g. arn:aws:execute-api:<region>:<account>:<api-id>/v1/GET/hello"
  value       = "${aws_api_gateway_stage.v1.execution_arn}/GET/hello"
}

# 呼び出し側に必要な IAM アクション（学習用）。
# この API を呼び出すには execute-api:Invoke 権限が必要。
output "required_iam_action" {
  description = "IAM action required to invoke this API. Attach to the caller's IAM policy."
  value       = "execute-api:Invoke"
}
