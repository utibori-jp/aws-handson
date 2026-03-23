# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
# =============================================================================

# 管理アカウントの AWS CLI プロファイル。他モジュールと命名を統一している。
variable "aws_profile" {
  description = "AWS CLI profile for the Organizations management account"
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

# SCP をアタッチする対象の OU ID。
# 未指定（null）の場合は Org ルート（r-xxxx）が自動的に使われる（main.tf の local.target_id 参照）。
# 特定の OU に限定したい場合は terraform.tfvars で指定する。
# 例: target_ou_id = "ou-xxxx-xxxxxxxx"
variable "target_ou_id" {
  description = "ID of the Organizations OU to attach SCPs to. If null, defaults to the Org root (from aws_organizations_organization data source)"
  type        = string
  default     = null
}
