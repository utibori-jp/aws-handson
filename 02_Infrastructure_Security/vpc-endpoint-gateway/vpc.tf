# =============================================================================
# vpc.tf — vpc-endpoint-gateway
# 演習専用 VPC をモジュール内で自包する。
#
# 【なぜ自包するか】
# 00_Baseline の VPC を参照する構成では、00_Baseline を apply していないと
# このモジュールが動作しない。Gateway Endpoint の演習は VPC 構成に依存しないため、
# 最小構成の VPC をここで完結させることで、モジュール単独で apply / destroy できる。
#
# 【NAT Gateway を持たない理由】
# Gateway Endpoint の学習目的は「NAT Gateway を経由せずに S3 へアクセスする」こと。
# NAT Gateway を置くと演習の意図が薄れるうえ、コストも発生する。
# プライベートサブネットのルートテーブルにはデフォルトルートを設けず、
# S3 向けトラフィックは Endpoint 経由のみとする構成にしている。
# =============================================================================

# ---
# VPC
# ---

resource "aws_vpc" "main" {
  cidr_block = local.vpc_cidr

  # DNS ホスト名を有効化しておく（EC2 接続時に便利）。
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

locals {
  vpc_cidr            = "10.1.0.0/16"
  private_subnet_cidr = "10.1.1.0/24"
}

# ---
# プライベートサブネット
# ---

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidr
  availability_zone = "${var.region}a"

  # パブリック IP は不要（プライベートサブネット）。
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

# ---
# ルートテーブル
# ---

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # デフォルトルート（0.0.0.0/0）は意図的に追加しない。
  # インターネットへの経路を持たないことで、S3 向けトラフィックが
  # Gateway Endpoint 経由に限定されることを確認できる。

  tags = {
    Name = "${var.project_name}-private-rtb"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
