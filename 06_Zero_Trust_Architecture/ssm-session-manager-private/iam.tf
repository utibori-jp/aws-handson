# =============================================================================
# iam.tf
# EC2 に付与する IAM ロール。
# SSM Session Manager の動作に必要な最小権限 + セッションログの S3 書き込み権限。
# =============================================================================

# EC2 が AssumeRole できるように信頼ポリシーを設定する。
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ssm-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ssm-ec2-role"
  }
}

# AmazonSSMManagedInstanceCore: SSM Agent が Systems Manager と通信するために必要。
# Session Manager / Run Command / Patch Manager など SSM 機能全般の基盤となるポリシー。
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# セッションログを S3 に書き込む権限。
# 最小権限原則に従い、対象バケット・プレフィックス・アカウントIDを限定している。
# SCS 的観点: s3:PutObject のみ許可し、GetObject / DeleteObject は付与しない。
resource "aws_iam_role_policy" "session_log_s3" {
  name = "session-log-s3-write"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PutSessionLogs"
        Effect = "Allow"
        Action = "s3:PutObject"
        # アカウント ID をパスに含めることで複数アカウントからログを集約するケースでも分離できる。
        Resource = "${aws_s3_bucket.session_logs.arn}/${local.account_id}/*"
      },
      {
        # SSM が S3 バケットの暗号化設定を確認するために必要。
        Sid      = "GetEncryptionConfig"
        Effect   = "Allow"
        Action   = "s3:GetEncryptionConfiguration"
        Resource = aws_s3_bucket.session_logs.arn
      }
    ]
  })
}

# インスタンスプロファイル: EC2 に IAM ロールをアタッチするためのラッパー。
resource "aws_iam_instance_profile" "main" {
  name = "${var.project_name}-ssm-ec2-profile"
  role = aws_iam_role.ec2.name
}
