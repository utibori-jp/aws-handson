# =============================================================================
# main.tf
# プロバイダ設定。terraform-sso（管理アカウント）で認証し、
# OrganizationAccountAccessRole 経由で learner / peer アカウントにリソースを作成する。
# =============================================================================

locals {
  learner_account_id = var.learner_account_id
  peer_account_id    = var.peer_account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"
}

# learner アカウント用プロバイダ（デフォルト）。
# このアカウントに caller ロールと AssumeRole 権限ポリシーを作成する。
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

# peer アカウント用プロバイダ（エイリアス付き）。
# このアカウントに cross-account ロールと信頼ポリシーを作成する。
# provider = aws.peer を明示したリソースがこのアカウントに作成される。
provider "aws" {
  alias   = "peer"
  region  = var.region
  profile = var.aws_profile  # terraform-sso（管理アカウント）で認証

  # リソースの着地先を peer アカウントに切り替える。
  # alias = "peer" を付与したこのプロバイダを provider = aws.peer で参照することで、
  # learner／peer の2アカウントに同一の apply でリソースを作り分けられる。
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
