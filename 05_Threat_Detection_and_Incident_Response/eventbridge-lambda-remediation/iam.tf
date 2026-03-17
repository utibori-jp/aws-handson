# =============================================================================
# iam.tf — eventbridge-lambda-remediation
# Lambda 実行ロール。修復に必要な最小権限のみを付与する。
#
# 【SCS 的観点：自動化ロールも最小権限】
# 自動修復 Lambda が過剰な権限を持つと、Lambda 自体が侵害された場合に
# 被害が拡大する。修復に必要な操作だけに絞ること。
#
# KMS 削除キャンセル Lambda: kms:CancelKeyDeletion + kms:EnableKey のみ
# SG ルール取り消し Lambda: ec2:RevokeSecurityGroupIngress + ec2:DescribeSecurityGroups のみ
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
# KMS 削除キャンセル Lambda 用ロール
# ---

resource "aws_iam_role" "cancel_kms_deletion" {
  name               = "${var.project_name}-cancel-kms-deletion-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-cancel-kms-deletion-role"
  }
}

resource "aws_iam_role_policy" "cancel_kms_deletion" {
  name = "${var.project_name}-cancel-kms-deletion-policy"
  role = aws_iam_role.cancel_kms_deletion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # KMS 削除予約のキャンセルと再有効化に必要な最小権限。
        # kms:ScheduleKeyDeletion は含めない（修復 Lambda が削除予約できないようにする）。
        Sid      = "CancelKmsDeletion"
        Effect   = "Allow"
        Action   = ["kms:CancelKeyDeletion", "kms:EnableKey", "kms:DescribeKey"]
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
        Resource = "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-cancel-kms-deletion:*"
      }
    ]
  })
}

# ---
# SG ルール取り消し Lambda 用ロール
# ---

resource "aws_iam_role" "revoke_sg_ingress" {
  name               = "${var.project_name}-revoke-sg-ingress-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-revoke-sg-ingress-role"
  }
}

resource "aws_iam_role_policy" "revoke_sg_ingress" {
  name = "${var.project_name}-revoke-sg-ingress-policy"
  role = aws_iam_role.revoke_sg_ingress.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # SG ルールの取り消しと確認に必要な最小権限。
        # ec2:AuthorizeSecurityGroupIngress は含めない（修復 Lambda がルールを追加できないようにする）。
        Sid    = "RevokeSgIngress"
        Effect = "Allow"
        Action = [
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeSecurityGroups",
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
        Resource = "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-revoke-sg-ingress:*"
      }
    ]
  })
}
