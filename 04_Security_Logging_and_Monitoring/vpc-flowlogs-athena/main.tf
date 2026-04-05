# =============================================================================
# main.tf
# プロバイダ設定・共通データソース・ローカル変数。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = "aws"
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile  # terraform-sso（管理アカウント）で認証

  # リソースの着地先を learner アカウントに切り替える。
  # provider は「認証したロールが属するアカウント」にリソースを作るため、
  # このブロックがないと管理アカウントにリソースが作られてしまう。
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
