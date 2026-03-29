# =============================================================================
# main.tf
# プロバイダ設定。管理アカウントの terraform-sso プロファイルから
# learner アカウントへ assume_role し、リソースを learner アカウントにデプロイする。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

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
