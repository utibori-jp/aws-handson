# =============================================================================
# main.tf
# プロバイダ設定・共通データソース・ローカル変数。
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = "aws"

  # vpc_id が指定されていれば既存 VPC を使い、なければ新規 VPC を使う。
  vpc_id = var.vpc_id != "" ? var.vpc_id : aws_vpc.test[0].id
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

# ---
# テスト用 VPC（vpc_id が未指定の場合のみ作成）
# ---
# 00_Baseline の VPC を使う場合は var.vpc_id に ID を渡すことでこのリソースはスキップされる。
# このモジュール単体での動作確認用として最小構成の VPC を用意する。

resource "aws_vpc" "test" {
  count      = var.vpc_id == "" ? 1 : 0
  cidr_block = "10.99.0.0/16"

  tags = {
    Name = "${var.project_name}-flowlogs-test-vpc"
  }
}
