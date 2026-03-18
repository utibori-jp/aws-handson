# =============================================================================
# verified_access.tf
# AWS Verified Access のリソース群。
#
# リソースの依存関係:
#   Instance → TrustProvider → Attachment → Group → Endpoint
#
# Zero Trust 的観点:
#   - VPN なしで認証済みユーザーのみがアプリにアクセスできる
#   - Trust Provider (IAM Identity Center) がユーザーのアイデンティティを保証する
#   - アクセスポリシーは Cedar 言語で記述し、属性ベースの細かい制御が可能
# =============================================================================

# IAM Identity Center インスタンス情報の取得。
# アカウントに Identity Center が有効化されていない場合はここでエラーになる。
data "aws_ssoadmin_instances" "main" {}

# 1. Verified Access インスタンス: 複数の Trust Provider と Group を束ねるコンテナ。
resource "aws_verifiedaccess_instance" "main" {
  description = "Verified Access instance for Zero Trust hands-on"

  tags = {
    Name = "${var.project_name}-verified-access-instance"
  }
}

# 2. Trust Provider: ユーザーアイデンティティの検証方法を定義する。
#    IAM Identity Center を使うことで、SSO で認証済みのユーザーが対象になる。
resource "aws_verifiedaccess_trust_provider" "idc" {
  trust_provider_type      = "user"
  user_trust_provider_type = "iam-identity-center"

  # policy_reference_name: アクセスポリシー内でこのプロバイダの属性を参照するときの変数名。
  # 例: idc.user.email や idc.groups でポリシーを書ける。
  policy_reference_name = "idc"

  description = "IAM Identity Center trust provider"

  tags = {
    Name = "${var.project_name}-va-trust-provider-idc"
  }
}

# 3. Trust Provider を Verified Access Instance にアタッチする。
resource "aws_verifiedaccess_instance_trust_provider_attachment" "main" {
  verifiedaccess_instance_id       = aws_verifiedaccess_instance.main.id
  verifiedaccess_trust_provider_id = aws_verifiedaccess_trust_provider.idc.id
}

# 4. Verified Access Group: アクセスポリシーの単位。
#    policy_document に Cedar ポリシーを記述する。
#    "permit(principal, action, resource);" は認証済み全ユーザーを許可する最もシンプルなポリシー。
#    本番では idc.user.email や idc.groups を使って特定ユーザーやグループのみに絞る。
resource "aws_verifiedaccess_group" "main" {
  verifiedaccess_instance_id = aws_verifiedaccess_instance.main.id

  # Cedar ポリシー: 認証されたプリンシパル全員に許可。
  # 本番例: permit(principal, action, resource) when { context.idc.groups.contains("engineers") };
  policy_document = "permit(principal, action, resource);"

  description = "Default group - allow all authenticated users"

  tags = {
    Name = "${var.project_name}-va-group"
  }

  depends_on = [aws_verifiedaccess_instance_trust_provider_attachment.main]
}

# 5. Verified Access Endpoint: 実際にトラフィックを受け付けるエンドポイント。
#    endpoint_type = "network-interface" により ALB なしで EC2 ENI に直接転送できる。
#    HTTPS で受けて HTTP (port 80) でバックエンドに転送する TLS ターミネーションを行う。
resource "aws_verifiedaccess_endpoint" "main" {
  application_domain    = var.application_domain
  domain_certificate_arn = var.domain_certificate_arn
  attachment_type                    = "vpc"

  # network-interface: EC2 の ENI を直接バックエンドに指定する。ALB が不要になる。
  endpoint_type = "network-interface"

  # endpoint_domain_prefix: Verified Access が生成する DNS 名のプレフィックス。
  # 実際の DNS 名は <prefix>.<endpoint-id>.go-to.amazonaws.com のような形式になる。
  endpoint_domain_prefix = "app"

  verified_access_group_id = aws_verifiedaccess_group.main.id
  security_group_ids       = [aws_security_group.va_endpoint.id]

  network_interface_options {
    network_interface_id = var.ec2_network_interface_id
    port                 = 80
    protocol             = "http"
  }

  description = "Verified Access endpoint for nginx backend (Module 1 EC2)"

  tags = {
    Name = "${var.project_name}-va-endpoint"
  }
}
