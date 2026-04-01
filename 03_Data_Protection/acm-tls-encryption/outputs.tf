# =============================================================================
# outputs.tf
# apply 後に確認コマンドで参照するリソース識別情報を出力する。
# =============================================================================

# ---
# ACM
# ---

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.main.arn
}

# ---
# ALB
# ---

output "alb_dns_name" {
  description = "DNS name of the ALB (use for HTTP→HTTPS redirect test)"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.main.arn
}

# ---
# Lambda
# ---

output "lambda_function_name" {
  description = "Name of the Lambda backend function"
  value       = aws_lambda_function.backend.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda backend function"
  value       = aws_lambda_function.backend.arn
}

