# =============================================================================
# sg.tf — vpc-endpoint-gateway
# EC2 インスタンス用と SSM Interface Endpoint 用のセキュリティグループを定義する。
#
# 【SSM Session Manager の通信方向】
# EC2 → SSM Interface Endpoint（HTTPS 443/tcp）の片方向のみ。
# SSM エージェントが Endpoint に対してポーリングする構造のため、
# EC2 SG にインバウンドルールは不要。
# =============================================================================

# ---
# EC2 用セキュリティグループ
# ---

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 test instance"
  vpc_id      = aws_vpc.main.id

  # SSM Session Manager は EC2 → Interface Endpoint への送信のみ使用するため、
  # インバウンドルールは不要。キーペアなしの構成と合わせて、
  # 「SSH ポートを開かずに接続できる」SCS 的観点のポイント。
  egress {
    description     = "HTTPS to SSM Interface Endpoints within VPC"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = [local.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

# ---
# SSM Interface Endpoint 用セキュリティグループ
# ---

resource "aws_security_group" "ssm_endpoints" {
  name        = "${var.project_name}-ssm-endpoints-sg"
  description = "Security group for SSM Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  # EC2 SG からの HTTPS のみ受け付ける。
  # ソースを CIDR ではなく SG ID で指定することで、
  # 許可するリソースを「このモジュールの EC2」に限定できる。
  ingress {
    description     = "HTTPS from EC2 instances"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = {
    Name = "${var.project_name}-ssm-endpoints-sg"
  }
}
