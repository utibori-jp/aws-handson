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

# リソース名のプレフィックスに使用する。
variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "scs-handson"
}

# SNS 通知の送信先メールアドレス。
# 空文字列の場合は SNS サブスクリプションを作成しない。
# 指定した場合は apply 後に確認メール（Subscription Confirmation）が届くため、
# メール内のリンクをクリックして購読を確認すること。
variable "alert_email" {
  description = "Email address to receive GuardDuty alert notifications (leave empty to skip subscription)"
  type        = string
  default     = ""
}
