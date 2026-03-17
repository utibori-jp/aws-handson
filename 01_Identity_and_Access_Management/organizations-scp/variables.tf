# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
# =============================================================================

# Organizations 管理アカウントの AWS CLI プロファイル。
variable "management_profile" {
  description = "AWS CLI profile for the Organizations management account"
  type        = string
  default     = "management-sso"
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
# 例: ou-xxxx-xxxxxxxx（マネジメントコンソール > Organizations > OU の詳細から確認）
# terraform plan のみ実行する場合はダミー値のままでよい。
variable "target_ou_id" {
  description = "ID of the Organizations OU to attach SCPs to (e.g. ou-xxxx-xxxxxxxx)"
  type        = string
  default     = "ou-xxxx-xxxxxxxx"
}
