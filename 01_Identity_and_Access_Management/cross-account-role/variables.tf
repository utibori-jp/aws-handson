# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
# source_profile / target_profile は terraform apply 時に -var で上書きする。
# =============================================================================

# ロールを引き受ける側（ソース）アカウントの AWS CLI プロファイル。
variable "source_profile" {
  description = "AWS CLI profile for the source account (the one assuming the role)"
  type        = string
  default     = "source-sso"
}

# ロールが存在する側（ターゲット）アカウントの AWS CLI プロファイル。
variable "target_profile" {
  description = "AWS CLI profile for the target account (the one hosting the role)"
  type        = string
  default     = "target-sso"
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
