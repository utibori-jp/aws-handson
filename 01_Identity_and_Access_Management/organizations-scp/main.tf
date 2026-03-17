# =============================================================================
# main.tf
# Organizations 管理アカウント用のプロバイダ設定。
# SCP の作成・アタッチには管理アカウントの認証情報が必要。
# =============================================================================

# 管理アカウントの ID を確認用に取得する。
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"
}

provider "aws" {
  region  = var.region
  profile = var.management_profile

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "SCS-Study"
    }
  }
}
