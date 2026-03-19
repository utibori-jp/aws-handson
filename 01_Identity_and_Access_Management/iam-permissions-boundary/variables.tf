# =============================================================================
# variables.tf
# 本モジュール全体で使用する入力変数。
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

# リソース名のプレフィックスに使用する。
# 共有アカウントで実行する場合は既存リソースと名前が被らないように変更すること。
variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "scs-handson"
}

# ---
# 00_Baseline 連携（任意）
# ---
# 以下の2変数を指定すると、developer_boundary を learner-admin PermissionSet に直接アタッチする。
# 00_Baseline の terraform output で取得できる値を使用する。
#
#   sso_instance_arn=$(cd ../../00_Baseline && terraform output -raw sso_instance_arn)
#   learner_admin_permission_set_arn=$(cd ../../00_Baseline && terraform output -raw learner_admin_permission_set_arn)
#
# 指定しない場合（null のまま）は PermissionSet アタッチをスキップする。
# その場合は下記フォールバック（developer ロールへの AssumeRole）で検証できる。

variable "sso_instance_arn" {
  description = "ARN of the IAM Identity Center instance (from 00_Baseline). Required to attach the boundary to the learner-admin PermissionSet."
  type        = string
  default     = null
}

variable "learner_admin_permission_set_arn" {
  description = "ARN of the learner-admin PermissionSet (from 00_Baseline). Required to attach the boundary to the learner-admin PermissionSet."
  type        = string
  default     = null
}
