provider "aws" {
  region  = "ap-northeast-1"
  profile = "terraform-sso"
}

data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current
}
