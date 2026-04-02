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

# リソース名・S3バケット名のプレフィックスに使用する。
# S3バケット名はグローバルユニークなため、共有アカウントでは重複しない名前に変更すること。
variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "scs-handson"
}

variable "learner_account_id" {
  description = "AWS account ID of the learner member account (from 00_Baseline: terraform output learner_account_id)"
  type        = string
}

# SNS 通知の送信先メールアドレス。
# 空文字列の場合は SNS サブスクリプションを作成しない。
variable "alert_email" {
  description = "Email address to receive CIS alarm notifications (leave empty to skip subscription)"
  type        = string
  default     = ""
}
