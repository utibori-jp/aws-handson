# =============================================================================
# main.tf
# プロバイダ設定。認証にはAWS SSOプロファイルを使用し、
# 全リソースに共通タグ（Project / ManagedBy / Environment）を強制付与する。
# =============================================================================

# 複数ファイルから参照する共通データを一箇所で定義する。
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  # GovCloudや中国リージョンに対応する場合は data "aws_partition" に差し替えること。
  partition = "aws"
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  # default_tags を使うことで、各リソースの tags ブロックに書かなくても
  # 全リソースに共通タグが自動付与される。
  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "SCS-Study"
    }
  }
}
