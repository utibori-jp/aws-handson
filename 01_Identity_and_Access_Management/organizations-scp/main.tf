# =============================================================================
# main.tf
# Organizations 管理アカウント用のプロバイダ設定。
# SCP の作成・アタッチには管理アカウントの認証情報が必要。
# 00_Baseline が apply 済みであることが前提（terraform-sso プロファイルで管理アカウントに接続）。
#
# 【前提条件】SCP ポリシータイプの有効化（初回のみ）
# AWS Organizations で SCP を使うには、ポリシータイプを事前に有効化する必要がある。
# 以下のコマンドを一度実行しておくこと（冪等。有効化済みでも安全）:
#
#   ROOT_ID=$(aws organizations list-roots \
#     --profile terraform-sso \
#     --query 'Roots[0].Id' --output text)
#   aws organizations enable-policy-type \
#     --root-id $ROOT_ID \
#     --policy-type SERVICE_CONTROL_POLICY \
#     --profile terraform-sso
#
# 有効化の確認:
#   aws organizations list-roots \
#     --profile terraform-sso \
#     --query 'Roots[0].PolicyTypes'
#   # → [{"Type": "SERVICE_CONTROL_POLICY", "Status": "ENABLED"}]
# =============================================================================

# 管理アカウントの ID を確認用に取得する。
data "aws_caller_identity" "current" {}

# SCP のアタッチ先となる Organizations のルート ID を取得する。
# target_ou_id が未指定の場合は Org ルートをデフォルトのアタッチ先とする。
data "aws_organizations_organization" "main" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"

  # target_ou_id が指定されていれば OU に、未指定なら Org ルートにアタッチする。
  target_id = coalesce(var.target_ou_id, data.aws_organizations_organization.main.roots[0].id)
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
