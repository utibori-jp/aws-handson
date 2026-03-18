# =============================================================================
# security_group.tf
# VPC Interface エンドポイント用 SG と EC2 用 SG の 2 つを定義する。
#
# 設計のポイント:
#   - EC2 はインバウンドを一切許可しない（SSH ポートも不要）
#   - EC2 のアウトバウンドはエンドポイント SG の 443 のみに限定
#   - エンドポイントはVPC内からの443のみを受け付ける
# =============================================================================

# --- VPC Interface エンドポイント用 SG ---

resource "aws_security_group" "endpoint" {
  name        = "${var.project_name}-ssm-endpoint-sg"
  description = "Allow HTTPS from within the VPC to SSM Interface Endpoints"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-ssm-endpoint-sg"
  }
}

# VPC 内からの HTTPS のみ許可。
# EC2 → エンドポイント間の TLS 通信 (443) を通す。
resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  security_group_id = aws_security_group.endpoint.id
  description       = "Allow HTTPS from VPC CIDR"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

# エンドポイント SG のアウトバウンドはデフォルト(全許可)のままとする。
# エンドポイントは AWS のマネージドサービスへのトラフィックを仲介するため制限不要。
resource "aws_vpc_security_group_egress_rule" "endpoint_all" {
  security_group_id = aws_security_group.endpoint.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- EC2 用 SG ---

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ssm-ec2-sg"
  description = "EC2 instance SG for SSM Session Manager - no inbound required"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-ssm-ec2-sg"
  }
}

# インバウンドは意図的に全て拒否（SG のデフォルト動作）。
# SSH (22) を開けないことが Zero Trust アーキテクチャの核心。

# EC2 から SSM Interface エンドポイントへの HTTPS のみ許可。
# SSM Agent は AWS Systems Manager の API を HTTPS で呼び出す。
# SCS 的観点: アウトバウンドも最小化することで不審な通信を抑制できる。
resource "aws_vpc_security_group_egress_rule" "ec2_to_endpoint" {
  security_group_id            = aws_security_group.ec2.id
  description                  = "Allow HTTPS to SSM Interface Endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoint.id
}
