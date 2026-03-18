# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
# vpc_id と private_subnet_ids は 00_Baseline の terraform output から取得する。
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

# 00_Baseline の terraform output vpc_id から取得する。
variable "vpc_id" {
  description = "VPC ID for ECS tasks (from 00_Baseline outputs)"
  type        = string
}

# 00_Baseline の terraform output private_subnet_ids から取得する。
# ECS Fargate タスクはプライベートサブネットに配置する（インターネットから直接到達不可）。
variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks (from 00_Baseline outputs)"
  type        = list(string)
}
