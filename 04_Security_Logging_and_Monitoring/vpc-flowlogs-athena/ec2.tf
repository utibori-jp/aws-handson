# =============================================================================
# ec2.tf — vpc-flowlogs-athena
# フローログの記録対象トラフィックを発生させる EC2 インスタンス。
#
# 【なぜ EC2 を置くか】
# VPC フローログは ENI を通過するトラフィックを記録する。
# EC2 を起動すると ENI が生成され、dnf リポジトリへのアウトバウンド通信などが
# 自動的に発生するため、フローログの動作確認に使える。
#
# 【セキュリティグループの設計】
# インバウンドルールを持たないことで、外部からのスキャンや接続試行が
# REJECT ログとして記録される。ACCEPT（アウトバウンド）と REJECT（インバウンド）
# 両方のログを Athena で確認できる。
#
# 【確認ポイント】
# 1. apply 後、フローログが S3 に届くまで約 10 分待つ。
#
# 2. ローカルから REJECT ログを意図的に発生させる。
#    curl http://<public_ip>   # HTTP アクセス試行（ポート 80 が REJECT される）
#    nmap -Pn <public_ip>      # ポートスキャン（各ポートが REJECT される）
#    ※ public_ip は terraform output public_ip で確認できる。
#
# 3. Athena コンソール右上のワークグループを "<project_name>-flowlogs" に切り替える。
#    デフォルトの "primary" ワークグループでは保存済みクエリが表示されない。
#
# 4. 「保存済みクエリ」から以下を選んで実行する。
#    - <project_name>-rejected-inbound   : 手順 2 で発生させた REJECT ログを確認
#    - <project_name>-outbound-from-ec2  : EC2 の自動アウトバウンド通信を確認
#    各クエリの WHERE 句のプレースホルダを terraform output の値に書き換えてから実行すること。
# =============================================================================

# 最新の Amazon Linux 2023 AMI を動的取得する。
# AMI ID はリージョン・時期によって異なるため、固定値を避けて data source で解決する。
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---
# セキュリティグループ
# ---

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-flowlogs-ec2-sg"
  description = "Allow all outbound, no inbound"
  vpc_id      = aws_vpc.main.id

  # アウトバウンドは全開放。SSM Agent・dnf 等のインターネット通信を許可する。
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # インバウンドルールは意図的に設けない。
  # 外部からの通信はすべて REJECT され、フローログに記録される。

  tags = {
    Name = "${var.project_name}-flowlogs-ec2-sg"
  }
}

# ---
# EC2 インスタンス
# ---

resource "aws_instance" "main" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.nano"
  subnet_id     = aws_subnet.public.id

  vpc_security_group_ids = [aws_security_group.ec2.id]

  # IMDSv2 を強制する。
  # IMDSv1 を許可すると SSRF 攻撃でインスタンスメタデータ（IAM 認証情報を含む）を
  # 外部から窃取できる。http_tokens = "required" で PUT トークン方式のみを受け付ける。
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_name}-flowlogs-ec2"
  }
}
