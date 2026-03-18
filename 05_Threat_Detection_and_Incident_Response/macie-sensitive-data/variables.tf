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

variable "alert_email" {
  description = "Email address to receive Macie alert notifications (leave empty to skip subscription)"
  type        = string
  default     = ""
}
