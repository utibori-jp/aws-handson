# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
# learner_account_id は 00_Baseline の terraform output から取得する。
# VPC は自包のため、vpc_id / route_table_ids は不要。
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

variable "learner_account_id" {
  description = "Learner account ID to deploy resources into (from 00_Baseline: terraform output learner_account_id)"
  type        = string
}
