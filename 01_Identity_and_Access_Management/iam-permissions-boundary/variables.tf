# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
# =============================================================================

# AWS SSOで作成したプロファイル名。aws configure sso で設定したものを指定する。
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

# リソース名のプレフィックスに使用する。
# 共有アカウントで実行する場合は既存リソースと名前が被らないように変更すること。
variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "scs-handson"
}

# ---
# 00_Baseline 連携（必須）
# ---
# 以下の値は 00_Baseline の terraform output から取得する。
#
#   cd ../../00_Baseline
#   terraform output sso_instance_arn
#   terraform output learner_admin_permission_set_arn

variable "sso_instance_arn" {
  description = "ARN of the IAM Identity Center instance (from 00_Baseline: terraform output sso_instance_arn)"
  type        = string
}

variable "learner_admin_permission_set_arn" {
  description = "ARN of the learner-admin PermissionSet (from 00_Baseline: terraform output learner_admin_permission_set_arn)"
  type        = string
}
