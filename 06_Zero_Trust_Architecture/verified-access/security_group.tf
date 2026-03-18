# =============================================================================
# security_group.tf
# Verified Access エンドポイント用セキュリティグループ。
#
# Verified Access はエンドポイントに SG をアタッチし、そこで受けたトラフィックを
# バックエンド（EC2 ENI）に転送する。バックエンドの EC2 SG では
# この SG からのトラフィックを許可するルールを追加すること（このモジュール外）。
# =============================================================================

resource "aws_security_group" "va_endpoint" {
  name        = "${var.project_name}-verified-access-sg"
  description = "Verified Access endpoint - allow HTTPS from internet"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-verified-access-sg"
  }
}

# インターネットからの HTTPS を受け付ける。
# Verified Access がユーザー認証・認可を行い、通過した場合のみバックエンドに転送する。
# SCS 的観点: 認証なしのリクエストは Verified Access レイヤーで遮断される。
resource "aws_vpc_security_group_ingress_rule" "va_https" {
  security_group_id = aws_security_group.va_endpoint.id
  description       = "Allow HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# バックエンド EC2 へ転送するためのアウトバウンド。
# EC2 の nginx は port 80 で待機している。
resource "aws_vpc_security_group_egress_rule" "va_to_backend" {
  security_group_id = aws_security_group.va_endpoint.id
  description       = "Allow HTTP to backend EC2 nginx"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}
