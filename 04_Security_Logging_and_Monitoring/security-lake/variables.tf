# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
# =============================================================================

variable "aws_profile" {
  description = "AWS CLI profile to use for authentication"
  type        = string
  default     = "terraform-sso"
}

variable "region" {
  description = "AWS region to deploy Security Lake"
  type        = string
  default     = "ap-northeast-1"
}

# リソース名・KMS エイリアスのプレフィックスに使用する。
variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "scs-handson"
}

variable "learner_account_id" {
  description = "AWS account ID of the learner member account (from 00_Baseline: terraform output learner_account_id)"
  type        = string
}

# Athena から Security Lake テーブルにアクセスするために Lake Formation 管理者として登録するロール ARN。
# IAM Identity Center（SSO）で learner-admin 権限セットに紐づく SSO ロール ARN を指定する。
# 取得方法:
#   aws iam list-roles \
#     --profile learner-admin \
#     --query 'Roles[?starts_with(RoleName, `AWSReservedSSO_scs-handson-learner-admin`)].Arn' \
#     --output text
variable "lakeformation_admin_role_arn" {
  description = "ARN of the IAM role to register as Lake Formation admin (SSO learner-admin role)"
  type        = string
}
