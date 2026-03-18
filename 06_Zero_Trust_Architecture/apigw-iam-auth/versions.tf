# =============================================================================
# versions.tf
# Terraform / OpenTofu バージョン制約とプロバイダバージョンのピン留め。
# archive プロバイダは Lambda の ZIP パッケージ生成に使用する。
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}
