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
