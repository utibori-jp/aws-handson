# =============================================================================
# vpc.tf — vpc-flowlogs-athena
# 演習専用 VPC をモジュール内で自包する。
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block = "10.99.0.0/16"

  tags = {
    Name = "${var.project_name}-flowlogs-vpc"
  }
}

# ---
# インターネットゲートウェイ
# ---

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-flowlogs-igw"
  }
}

# ---
# パブリックサブネット
# ---

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.99.1.0/24"
  availability_zone = "${var.region}a"

  # EC2 に自動でパブリック IP を付与する。インターネット経由のトラフィックを発生させるために必要。
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-flowlogs-public-subnet"
  }
}

# ---
# ルートテーブル
# ---

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-flowlogs-public-rtb"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
