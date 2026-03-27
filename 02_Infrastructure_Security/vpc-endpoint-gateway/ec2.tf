# =============================================================================
# ec2.tf — vpc-endpoint-gateway
# S3 Gateway Endpoint と SSM Interface Endpoint の動作確認用 EC2 インスタンスを作成する。
#
# 【キーペアなし・SSM のみでアクセスする理由】
# 踏み台サーバーや SSH ポート開放を廃止し、SSM Session Manager 経由でのみ
# アクセスする構成。これが SCS で重視される「ゼロトラスト的アクセス制御」の実践。
# - SSH (22/tcp) を開放しない → 攻撃面の縮小
# - Session Manager のセッションログを CloudTrail で記録可能
# - インターネット接続不要（Interface Endpoint 経由で AWS API に到達）
# =============================================================================

# ---
# IAM ロール（EC2 用）
# ---

# EC2 サービスが AssumeRole できるようにする信頼ポリシー。
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name               = "${var.project_name}-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# SSM Session Manager の動作に必要な最小権限ポリシー。
# ssm:UpdateInstanceInformation, ssmmessages:* などを含む AWS 管理ポリシー。
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 の動作確認用インラインポリシー。
# EC2 の IAM ロールに S3 権限を付与することで、インスタンスプロファイル経由でアクセスできる。
# （ssm start-session の --profile はセッション確立のみに使われ、EC2 内には引き継がれない）
# エンドポイントポリシーとの AND で有効権限が決まる点を確認するためのポリシー。
resource "aws_iam_role_policy" "ec2_s3" {
  name = "${var.project_name}-ec2-s3-policy"
  role = aws_iam_role.ec2_ssm.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:GetBucketLocation"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# ---
# AMI（最新の Amazon Linux 2023）
# ---

# 動的取得により、apply のたびに最新 AMI を使用する。
# Amazon Linux 2023 は SSM エージェントがデフォルトインストール済み。
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ---
# EC2 インスタンス
# ---

resource "aws_instance" "test" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.private.id

  # キーペアなし。SSH ではなく SSM Session Manager でのみアクセスする。
  key_name = null

  # パブリック IP は不要。SSM Interface Endpoint 経由でインターネット不要。
  associate_public_ip_address = false

  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name
  vpc_security_group_ids = [aws_security_group.ec2.id]

  tags = {
    Name = "${var.project_name}-test-instance"
  }
}
