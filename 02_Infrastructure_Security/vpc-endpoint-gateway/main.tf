# =============================================================================
# main.tf
# プロバイダ設定。認証にはAWS SSOプロファイルを使用し、
# learner アカウントに assume_role してリソースをデプロイする。
# 全リソースに共通タグ（Project / ManagedBy / Environment）を強制付与する。
# =============================================================================

# 複数ファイルから参照する共通データを一箇所で定義する。
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"
}

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

# エンドポイントポリシーの Deny を証明するための peer アカウント用プロバイダ。
# peer アカウントに S3 バケットを作成し、learner EC2 ロールからの ListBucket を許可する。
# エンドポイントポリシーがなければアクセスできるが、DenyOtherAccountS3 で遮断されることを確認できる。
provider "aws" {
  alias   = "peer"
  region  = var.region
  profile = var.aws_profile

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
