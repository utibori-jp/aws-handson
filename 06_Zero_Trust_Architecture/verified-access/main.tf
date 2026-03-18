# =============================================================================
# main.tf
# プロバイダ設定と共通ローカル変数。
# AWS Verified Access は VPN レスで社内アプリへのゼロトラストアクセスを実現する。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = "aws"
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
