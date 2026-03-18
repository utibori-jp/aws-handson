# =============================================================================
# variables.tf
# このモジュールへの入力変数。
# VPC 関連は 00_Baseline/vpc-base の outputs から取得すること。
# =============================================================================

# --- 共通 3 変数 ---

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

# --- ネットワーク変数 ---

variable "vpc_id" {
  description = "ID of the VPC where the EC2 instance and VPC endpoints will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs to deploy the EC2 instance and VPC endpoints into"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Used to allow HTTPS from within the VPC to the Interface endpoints."
  type        = string
}
