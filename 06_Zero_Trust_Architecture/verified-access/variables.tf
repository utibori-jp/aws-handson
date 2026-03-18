# =============================================================================
# variables.tf
# 前提条件:
#   1. IAM Identity Center がこのアカウント内で有効化済みであること
#   2. ACM パブリック証明書（ドメイン検証済み）の ARN を用意すること
#   3. application_domain への CNAME を Verified Access エンドポイントの DNS 名に向けること
# =============================================================================

variable "aws_profile" {
  description = "AWS CLI profile to use for authentication"
  type        = string
  default     = "terraform-sso"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "scs-handson"
}

variable "vpc_id" {
  description = "ID of the VPC where the Verified Access endpoint will be deployed"
  type        = string
}

# ssm-session-manager-private モジュールの outputs.primary_network_interface_id を指定する。
variable "ec2_network_interface_id" {
  description = "Primary ENI ID of the EC2 instance (nginx backend). Use ssm-session-manager-private output."
  type        = string
}

# Verified Access エンドポイントにアクセスするカスタムドメイン名。
# 例: app.example.com
# apply 後に出力される verified_access_endpoint_dns への CNAME レコードを追加すること。
variable "application_domain" {
  description = "Custom domain name for the Verified Access endpoint (e.g. app.example.com)"
  type        = string
}

# ACM パブリック証明書の ARN。application_domain と一致するドメインで発行済みであること。
# 例: arn:aws:acm:ap-northeast-1:<account>:certificate/<uuid>
variable "domain_certificate_arn" {
  description = "ARN of an ACM public certificate valid for application_domain"
  type        = string
}
