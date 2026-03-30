# =============================================================================
# main.tf
# プロバイダ設定。
# KMS CMK は Peer アカウントに、S3 バケットは Learner アカウントに作成する。
# provider を2つ定義することで、リソースを別アカウントに分散させる。
#
# 【このモジュールのアカウント構成】
# Peer アカウント（デフォルト provider）: KMS CMK を所有・管理。
#   この検証では Peer アカウントが鍵管理アカウント（セキュリティチーム役）を担う。
# Learner アカウント（aws.learner provider）: S3 バケットを所有し、Peer の CMK でデータを暗号化（アプリチーム役）。
#   検証操作はすべて Learner アカウント（learner-admin）から実行する。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"
}

# Peer アカウント：KMS CMK の作成に使用（デフォルトプロバイダ）
# この検証では Peer アカウントが鍵管理アカウント（セキュリティチーム）を担う。
provider "aws" {
  region  = var.region
  profile = var.aws_profile # terraform-sso（管理アカウント）で認証したうえで assume_role

  assume_role {
    role_arn = "arn:aws:iam::${var.peer_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "SCS-Study"
    }
  }
}

# Learner アカウント：S3 バケットの作成に使用
# Peer アカウントの CMK でデータを暗号化する（アプリチーム役）。
provider "aws" {
  alias   = "learner"
  region  = var.region
  profile = var.aws_profile # terraform-sso（管理アカウント）で認証したうえで assume_role

  assume_role {
    role_arn = "arn:aws:iam::${var.learner_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "SCS-Study"
    }
  }
}
