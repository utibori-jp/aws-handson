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
  description = "AWS region for the S3 origin bucket (WAF is always created in us-east-1)"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "scs-handson"
}

variable "learner_account_id" {
  description = "AWS account ID of the learner member account (from 00_Baseline: terraform output learner_account_id)"
  type        = string
}
