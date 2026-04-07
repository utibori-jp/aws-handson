# =============================================================================
# main.tf
# プロバイダ設定・共通データソース・ローカル変数。
#
# 【プロバイダ構成（3アカウント）】
# このモジュールは以下の3つのプロバイダを使う。
#
# provider "aws" (default)
#   → Learner アカウント。Config・Security Hub メンバー側のリソースを配置する。
#     既存モジュールと同じ単一アカウントパターン。
#
# provider "aws" { alias = "management" }
#   → 管理アカウント（assume_role なし）。
#     Security Hub の委任管理者指定（Organizations レベルの操作）はここで実行する。
#     ⚠️ このモジュールで唯一、管理アカウントに直接リソースを作るプロバイダ。
#     CLAUDE.md の「管理アカウントにリソースを置かない原則」の例外であり、
#     委任設定という Organizations 操作が管理アカウントでしか実行できないため許容する。
#
# provider "aws" { alias = "peer" }
#   → Peer アカウント。Security Hub 委任管理者側のリソースを配置する。
#     cross-account-role モジュールと同じ assume_role パターン。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用 AWS）を前提に "aws" で固定する。
  partition = "aws"
}

# Learner アカウント（リソースの主配置先）。
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

# 管理アカウント（Organizations 委任設定専用）。
# assume_role を使わず terraform-sso で直接認証するため、
# リソースは管理アカウント自身に着地する。
provider "aws" {
  alias   = "management"
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

# Peer アカウント（Security Hub 委任管理者）。
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
