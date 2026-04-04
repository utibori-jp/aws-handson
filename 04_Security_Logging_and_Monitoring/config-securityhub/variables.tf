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

variable "peer_account_id" {
  description = "AWS account ID of the peer member account used as Security Hub delegated administrator (from 00_Baseline: terraform output peer_account_id)"
  type        = string
}
