# =============================================================================
# main.tf
# プロバイダ設定。単一アカウント（Learner）構成。
# ACM 証明書・ALB・Lambda・S3 はすべて Learner アカウントの ap-northeast-1 に作成する。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"
}

provider "aws" {
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
