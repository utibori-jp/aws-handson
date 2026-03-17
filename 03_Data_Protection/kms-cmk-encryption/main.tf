# =============================================================================
# main.tf
# プロバイダ設定・共通データソース・ローカル変数。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # パーティションは東京リージョン（標準商用AWS）を前提に "aws" で固定する。
  partition = "aws"

  # 00_Baseline/iam.tf で作成した学習用 IAM ユーザーの ARN。
  # キーポリシーの AllowKeyUsage で「暗号化/復号を許可するプリンシパル」として使用する。
  # 00_Baseline を apply していない場合は、存在しないユーザー ARN がポリシーに残るだけで
  # キー自体の作成は問題なく完了する（AWS はキーポリシーのプリンシパル存在確認をしない）。
  learner_user_arn = "arn:${local.partition}:iam::${local.account_id}:user/${var.project_name}-learner"
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
