# =============================================================================
# main.tf
# 2つの AWS プロバイダを定義する：
#   - default: ap-northeast-1（S3 オリジン・CloudFront Distribution 管理用）
#   - aws.us_east_1: us-east-1（WAF Web ACL 専用）
#
# 【なぜ us-east-1 が必要か】
# CloudFront スコープの WAF Web ACL は us-east-1 にしか作成できない。
# これは CloudFront がグローバルサービスであり、WAF との統合が
# us-east-1 のコントロールプレーンを通じて行われるため。
# 01_IAM の cross-account-role と同じ「provider alias」パターンの応用。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"
}

# メインプロバイダ（ap-northeast-1）。
# S3 バケットと CloudFront Distribution の管理に使用する。
provider "aws" {
  region  = var.region
  profile = var.aws_profile  # terraform-sso（管理アカウント）で認証

  # リソースの着地先を learner アカウントに切り替える。
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

# WAF 専用プロバイダ（us-east-1）。
# CloudFront スコープの WAF Web ACL はこのプロバイダで作成する。
# waf.tf のリソースは provider = aws.us_east_1 を明示している。
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = var.aws_profile  # terraform-sso（管理アカウント）で認証

  # メインプロバイダと同じ learner アカウントに切り替える。
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
