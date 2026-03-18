# =============================================================================
# main.tf
# プロバイダ設定と共通ローカル変数。
# Zero Trust の第一歩: EC2 へのアクセスに SSH キーも踏み台も不要にする。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用 AWS）を前提に "aws" で固定する。
  partition = "aws"
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "SCS-Study"
    }
  }
}
