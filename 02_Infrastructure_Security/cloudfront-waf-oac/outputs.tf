# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

# ---
# CloudFront
# ---

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution (access via https://<domain>/index.html)"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}

# ---
# S3 Origin
# ---

output "origin_bucket_name" {
  description = "Name of the S3 origin bucket"
  value       = aws_s3_bucket.origin.bucket
}

output "origin_bucket_arn" {
  description = "ARN of the S3 origin bucket"
  value       = aws_s3_bucket.origin.arn
}

# ---
# WAF
# ---

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL (us-east-1)"
  value       = aws_wafv2_web_acl.cloudfront.arn
}

# アクセス確認用 URL。
output "access_url" {
  description = "URL to access the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/index.html"
}
