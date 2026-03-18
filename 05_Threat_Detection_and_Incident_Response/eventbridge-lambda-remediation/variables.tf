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

# 修復操作の結果通知を受け取るメールアドレス（省略可）。
variable "alert_email" {
  description = "Email address to receive remediation result notifications (leave empty to skip)"
  type        = string
  default     = ""
}
