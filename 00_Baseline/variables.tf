# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
# デフォルト値はap-northeast-1（東京）リージョン、terraform-ssoプロファイルを前提とする。
# =============================================================================

# AWS SSOで作成したプロファイル名。aws configure sso で設定したものを指定する。
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

# リソース名やS3バケット名のプレフィックスに使用する。
# S3バケット名はグローバルでユニークである必要があるため、
# 共有アカウント（学習用サンドボックスなど）で実行する場合は、
# 既存リソースと名前が被らないように変更する。
variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "scs-handson"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# public_subnet_cidrs と availability_zones は同じ要素数にする必要がある。
# count.index で対応関係を持つため、順序も AZ と一致させること。
variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to deploy subnets into"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}
