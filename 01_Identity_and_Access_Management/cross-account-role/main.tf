# =============================================================================
# main.tf
# 2つの AWS プロバイダを定義する：
#   - default: ソースアカウント（ロールを引き受ける側）
#   - aws.target: ターゲットアカウント（ロールが存在する側）
#
# 【前提条件】
# - `aws configure sso` で source_profile / target_profile を設定済みであること
# - 詳細は README.md を参照
# =============================================================================

# ソースアカウントの ID を取得する（デフォルトプロバイダ）。
data "aws_caller_identity" "source" {}

# ターゲットアカウントの ID を取得する（エイリアスプロバイダ）。
data "aws_caller_identity" "target" {
  provider = aws.target
}

locals {
  source_account_id = data.aws_caller_identity.source.account_id
  target_account_id = data.aws_caller_identity.target.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"
}

# ソースアカウント用プロバイダ（デフォルト）。
# このアカウントに caller ユーザーと AssumeRole 権限ポリシーを作成する。
provider "aws" {
  region  = var.region
  profile = var.source_profile

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "SCS-Study"
    }
  }
}

# ターゲットアカウント用プロバイダ（エイリアス付き）。
# このアカウントに cross-account ロールと信頼ポリシーを作成する。
# alias = "target" と指定したリソースでは provider = aws.target を明示する。
provider "aws" {
  alias   = "target"
  region  = var.region
  profile = var.target_profile

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "SCS-Study"
    }
  }
}
