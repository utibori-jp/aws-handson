# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
# vpc_id と route_table_ids は 00_Baseline の terraform output から取得する。
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
# Gateway Endpoint はルートテーブルに自動でエントリを追加するため VPC ID が必要。
variable "vpc_id" {
  description = "VPC ID to attach the Gateway Endpoint (from 00_Baseline outputs)"
  type        = string
}

# 00_Baseline の terraform output public_subnet_ids / private_subnet_ids に対応するルートテーブル ID。
# Gateway Endpoint のルートをどのルートテーブルに追加するかを指定する。
# プライベートサブネットのルートテーブルを指定することで、
# EC2 インスタンスが NAT Gateway を経由せずに S3 へアクセスできるようになる。
variable "route_table_ids" {
  description = "List of route table IDs to associate with the Gateway Endpoint"
  type        = list(string)
}
