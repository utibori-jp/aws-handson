# =============================================================================
# vpc.tf — ecs-fargate-security
# 演習専用 VPC をモジュール内で自包する。
#
# 【なぜ自包するか】
# 00_Baseline の VPC は管理アカウントに作成されるが、このモジュールは
# learner アカウントへ assume_role してリソースをデプロイする。
# 管理アカウントの VPC を learner アカウントから参照することはできないため、
# このモジュール内で VPC を自包し、モジュール単独で apply / destroy できる構成にしている。
#
# 【なぜパブリックサブネットか】
# NAT Gateway を持たない最小コスト構成のため、ECS タスクに public IP を付与して
# インターネット経由で ECR Pull・CloudWatch Logs への書き込みを行う。
# inbound の SG ルールはなし（全拒否）のため、外部からコンテナへのアクセスは不可。
# =============================================================================

locals {
  vpc_cidr           = "10.2.0.0/16"
  public_subnet_cidr = "10.2.1.0/24"
}

# ---
# VPC
# ---

resource "aws_vpc" "main" {
  cidr_block = local.vpc_cidr

  # DNS ホスト名を有効化する（ECS のサービスディスカバリや SSM に必要）。
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ---
# インターネットゲートウェイ
# ---

# IGW 単体ではインターネット通信はできない。
# ルートテーブルで「0.0.0.0/0 → IGW」を設定して初めて有効になる（下記参照）。
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ---
# パブリックサブネット
# ---

# ECS タスクを配置するパブリックサブネット。
# map_public_ip_on_launch は ECS Fargate では効果がない（タスク定義側の assign_public_ip で制御）が、
# 将来 EC2 を配置する場合のために有効にしておく。
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_subnet_cidr
  availability_zone = "${var.region}a"

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
    Tier = "public"
  }
}

# ---
# ルートテーブル
# ---

# デフォルトルートを IGW に向けることでインターネット通信を可能にする。
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rtb"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
