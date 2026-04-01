# =============================================================================
# vpc.tf — acm-tls-encryption
# 演習専用 VPC をモジュール内で自包する。
# ALB はマルチ AZ 構成が必須のため、異なる AZ に 2 つのパブリックサブネットを作成する。
#
# 【自包 VPC を使う理由】
# Learner アカウントへ assume_role してリソースを作成するため、
# 管理アカウントや他モジュールの VPC を参照できない。
# モジュール単独で apply / destroy できる構成を維持するために自包する。
#
# 【CIDR の選定】
# 既存モジュールとの重複を避けて 10.3.0.0/16 を使用する。
# vpc-endpoint-gateway: 10.1.0.0/16、ecs-fargate-security: 10.2.0.0/16
# =============================================================================

locals {
  vpc_cidr             = "10.3.0.0/16"
  public_subnet_1_cidr = "10.3.1.0/24"
  public_subnet_2_cidr = "10.3.2.0/24"
}

resource "aws_vpc" "main" {
  cidr_block = local.vpc_cidr

  # ALB の DNS 名解決に必要。
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# インターネットゲートウェイ。
# パブリックサブネットからインターネットへの経路に必要。
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# パブリックサブネット 1（ap-northeast-1a）。
# ALB は最低 2 つの AZ にサブネットが必要なため 1a と 1c に 1 つずつ作成する。
resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_subnet_1_cidr
  availability_zone = "${var.region}a"

  # ALB ノードに自動でパブリック IP を付与する（インターネット向け ALB に必要）。
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-1a"
    Tier = "public"
  }
}

# パブリックサブネット 2（ap-northeast-1c）。
resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_subnet_2_cidr
  availability_zone = "${var.region}c"

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-1c"
    Tier = "public"
  }
}

# パブリックルートテーブル。
# デフォルトルート（0.0.0.0/0）を IGW に向けてインターネットアクセスを可能にする。
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

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}
