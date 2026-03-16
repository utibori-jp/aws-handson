# =============================================================================
# vpc.tf — vpc-base
# VPC・パブリック/プライベートサブネット・インターネットゲートウェイを構築する。
# NAT Gatewayは時間課金が発生するためベースライン環境では排除。
# =============================================================================

# DNS解決とDNSホスト名を有効化する。
# SSM Session ManagerのVPCエンドポイント（06章）や、ECSのサービスディスカバリが
# 正しく動作するために必要な設定。
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# インターネットゲートウェイをVPCにアタッチする。
# IGWをアタッチするだけではインターネット通信はできない。
# パブリックサブネットから IGW 経由でインターネットに出るには、
# ルートテーブルで「デフォルトルート（0.0.0.0/0）→ IGW」を設定する必要がある（下記参照）。
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ---
# サブネット
# ---

# パブリックサブネット（AZごとに1つ）。
# map_public_ip_on_launch = true により、起動したEC2に自動でパブリックIPが付与される。
# ALBやCloudFrontオリジン検証用インスタンスなど、外部からアクセスが必要なリソースを配置する。
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# プライベートサブネット（AZごとに1つ）。
# ECSタスクやRDSなど、直接インターネットに公開しないリソースを配置する。
# NAT Gatewayを持たないため、外向き通信が必要なワークロードは
# VPCエンドポイント（02章・06章）で代替する。
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# ---
# ルートテーブル
# ---

# パブリックサブネット用。デフォルトルートをIGWに向けることでインターネット通信を可能にする。
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rtb-public"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# プライベートサブネット用。NAT Gatewayなしのため外向きルートは持たない。
# インターネットへのアウトバウンドが必要な章では、その章でNAT Gatewayを追加すること。
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rtb-private"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
