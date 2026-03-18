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
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "scs-handson"
}

# VPC フローログを有効化する対象 VPC の ID。
# 00_Baseline の VPC ID を terraform output で取得して指定する。
# 空文字列の場合は新規 VPC を作成してフローログを有効化する。
variable "vpc_id" {
  description = "VPC ID to enable flow logs on. Leave empty to create a new test VPC."
  type        = string
  default     = ""
}
