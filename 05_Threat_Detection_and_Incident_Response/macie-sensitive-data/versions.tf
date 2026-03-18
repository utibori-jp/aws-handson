# =============================================================================
# versions.tf
# Terraform / OpenTofu バージョン制約とプロバイダバージョンのピン留め。
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
