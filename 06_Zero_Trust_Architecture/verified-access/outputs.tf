# =============================================================================
# outputs.tf
# Verified Access エンドポイントの情報を出力する。
# apply 後に endpoint_dns を CNAME レコードに設定すること。
# =============================================================================

# カスタムドメイン (application_domain) への CNAME レコードに指定する値。
# DNS プロバイダ (Route 53 等) で設定が必要。
output "verified_access_endpoint_dns" {
  description = "DNS name of the Verified Access endpoint. Set as CNAME for your application_domain."
  value       = aws_verifiedaccess_endpoint.main.endpoint_domain
}

output "verified_access_group_id" {
  description = "ID of the Verified Access group. Use to update access policies."
  value       = aws_verifiedaccess_group.main.id
}

output "verified_access_instance_id" {
  description = "ID of the Verified Access instance"
  value       = aws_verifiedaccess_instance.main.id
}
