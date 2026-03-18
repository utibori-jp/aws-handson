# =============================================================================
# iam.tf — guardduty-auto-remediation
# Lambda 実行ロール。修復に必要な最小権限のみを付与する。
#
# 【SCS 的観点：自動化ロールも最小権限】
# インシデントレスポンスの自動化では「修復 Lambda が過剰な権限を持たない」ことが重要。
# 攻撃者が Lambda 自体を侵害した場合に被害を最小化できる。
#
# IAM キー無効化 Lambda: iam:UpdateAccessKey + iam:ListAccessKeys のみ
# EC2 隔離 Lambda: ec2 の最小セット（Describe + Create/ModifyInstanceAttribute）のみ
# =============================================================================

# ---
# 共通の信頼ポリシー（Lambda AssumeRole）
# ---

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---
# IAM キー無効化 Lambda 用ロール
# ---

resource "aws_iam_role" "remediate_iam_key" {
  name               = "${var.project_name}-remediate-iam-key-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-remediate-iam-key-role"
  }
}

resource "aws_iam_role_policy" "remediate_iam_key" {
  name = "${var.project_name}-remediate-iam-key-policy"
  role = aws_iam_role.remediate_iam_key.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # IAM アクセスキーの無効化に必要な最小権限。
        # iam:CreateAccessKey / iam:DeleteAccessKey は含めない（職務分離）。
        Sid      = "DisableIAMKey"
        Effect   = "Allow"
        Action   = ["iam:UpdateAccessKey", "iam:ListAccessKeys"]
        Resource = "*"
      },
      {
        # CloudWatch Logs への書き込み（修復操作の証跡）。
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-remediate-iam-key:*"
      }
    ]
  })
}

# ---
# EC2 隔離 Lambda 用ロール
# ---

resource "aws_iam_role" "isolate_ec2" {
  name               = "${var.project_name}-isolate-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-isolate-ec2-role"
  }
}

resource "aws_iam_role_policy" "isolate_ec2" {
  name = "${var.project_name}-isolate-ec2-policy"
  role = aws_iam_role.isolate_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # EC2 隔離（セキュリティグループ差し替え）に必要な最小権限。
        # ec2:TerminateInstances は含めない。隔離と終了は別の決定プロセスで行う（SCS 頻出の設計思想）。
        Sid    = "IsolateEC2"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:CreateSecurityGroup",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-isolate-ec2:*"
      }
    ]
  })
}
