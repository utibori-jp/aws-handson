# =============================================================================
# ec2.tf
# プライベートサブネット内の EC2 インスタンス。
# キーペアなし・パブリック IP なし。アクセスは SSM Session Manager のみ。
# Module 3 (verified-access) のバックエンドとして nginx も起動する。
# =============================================================================

# 最新の Amazon Linux 2023 AMI を動的取得する。
# ハードコードすると AMI が古くなりセキュリティリスクになるため data source を使う。
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SCS 的観点: キーペアを使わないことで SSH ポート (22) を開く必要がなくなる。
# SSM Session Manager は AWS の管理プレーンを通じて接続するため、
# セキュリティグループでインバウンドを一切許可しなくてもセッションが確立できる。
resource "aws_instance" "main" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = var.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.main.name
  associate_public_ip_address = false # プライベートサブネット配置 — パブリック IP 不要
  # key_name は意図的に省略。SSH によるアクセスを排除することが Zero Trust の第一歩。

  # nginx を起動して Module 3 (Verified Access) のバックエンドを兼ねる。
  # user_data はインスタンス起動時に一度だけ実行される。
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
  EOF

  # user_data が変わってもインスタンスを再作成しない（学習環境では変更頻度が高いため）
  user_data_replace_on_change = false

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true # 保存データの暗号化 — SCS 必須要件
  }

  tags = {
    Name = "${var.project_name}-ssm-target"
  }
}
