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

# Finding Aggregator を有効化するかどうか。
# マルチアカウント・マルチリージョンのフィンディングを1リージョンに集約する機能。
# 単一アカウントのハンズオンでは不要なため、デフォルト false にしている。
# 将来的なマルチアカウント構成への拡張時に true にする。
variable "enable_finding_aggregator" {
  description = "Enable Security Hub finding aggregator for multi-region aggregation (not needed for single-account)"
  type        = bool
  default     = false
}
