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

# learner メンバーアカウントに割り当てるメールアドレス。
# AWS アカウントのメールアドレスはグローバルでユニークである必要がある。
# 新規メアドを用意しなくても、Gmail などのエイリアス機能（user+learner@gmail.com）で
# 既存のアドレスから派生させることができる。terraform-sso 作成時に使用したメアドに
# +learner などを付けた形式が手軽でおすすめ。
variable "learner_account_email" {
  description = "Email address for the learner Organizations member account (must be globally unique)"
  type        = string
}

# peer メンバーアカウントに割り当てるメールアドレス。
# learner_account_email と同様、Gmail エイリアス機能（user+peer@gmail.com）が手軽でおすすめ。
variable "peer_account_email" {
  description = "Email address for the peer Organizations member account (must be globally unique)"
  type        = string
}

# IAM Identity Center コンソールの「ユーザー」画面で確認できるユーザー名。
# 通常はメールアドレス形式（例: user@example.com）。
# terraform-sso のサインインに使用しているユーザーと同じで問題ない。
variable "sso_username" {
  description = "Username of the IAM Identity Center user to assign learner permission sets to"
  type        = string
}

