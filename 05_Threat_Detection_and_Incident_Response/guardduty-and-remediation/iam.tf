# =============================================================================
# iam.tf — guardduty-and-remediation
# Lambda 実行ロール。修復に必要な最小権限のみを付与する。
#
# 【SCS 的観点：自動化ロールも最小権限】
# 自動修復 Lambda が過剰な権限を持つと、Lambda 自体が侵害された場合に
# 被害が拡大する。修復に必要な操作だけに絞ること。
# ロールを Lambda ごとに分離することで、1 つの Lambda が侵害されても
# 他の Lambda の権限は使えない（職務分離）。
#
# 各ロールの権限：
# - cancel-kms-deletion-role: kms:CancelKeyDeletion + kms:EnableKey のみ（削除はできない）
# - revoke-sg-ingress-role:   ec2:RevokeSecurityGroupIngress + Describe のみ（追加はできない）
# - remediate-iam-key-role:   iam:UpdateAccessKey のみ（作成・削除はできない）
# - isolate-ec2-role:         ec2 の最小セット（終了・終了は含まない）
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

data "aws_iam_policy_document" "cancel_kms_deletion" {
  statement {
    # KMS 削除予約のキャンセルと再有効化に必要な最小権限。
    # kms:ScheduleKeyDeletion は含めない（修復 Lambda が削除予約できないようにする）。
    sid       = "CancelKmsDeletion"
    effect    = "Allow"
    actions   = ["kms:CancelKeyDeletion", "kms:EnableKey", "kms:DescribeKey"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-cancel-kms-deletion:*"]
  }

  statement {
    sid       = "AllowSNSPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.remediation_alerts.arn]
  }
}

resource "aws_iam_role" "cancel_kms_deletion" {
  name               = "${var.project_name}-cancel-kms-deletion-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-cancel-kms-deletion-role"
  }
}

resource "aws_iam_role_policy" "cancel_kms_deletion" {
  name   = "${var.project_name}-cancel-kms-deletion-policy"
  role   = aws_iam_role.cancel_kms_deletion.id
  policy = data.aws_iam_policy_document.cancel_kms_deletion.json
}

# ---
# SG ルール取り消し Lambda 用ロール
# ---

data "aws_iam_policy_document" "revoke_sg_ingress" {
  statement {
    # SG ルールの取り消しと確認に必要な最小権限。
    # ec2:AuthorizeSecurityGroupIngress は含めない（修復 Lambda がルールを追加できないようにする）。
    sid    = "RevokeSgIngress"
    effect = "Allow"
    actions = [
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DescribeSecurityGroups",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-revoke-sg-ingress:*"]
  }

  statement {
    sid       = "AllowSNSPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.remediation_alerts.arn]
  }
}

resource "aws_iam_role" "revoke_sg_ingress" {
  name               = "${var.project_name}-revoke-sg-ingress-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-revoke-sg-ingress-role"
  }
}

resource "aws_iam_role_policy" "revoke_sg_ingress" {
  name   = "${var.project_name}-revoke-sg-ingress-policy"
  role   = aws_iam_role.revoke_sg_ingress.id
  policy = data.aws_iam_policy_document.revoke_sg_ingress.json
}

# ---
# IAM キー無効化 Lambda 用ロール
# ---

data "aws_iam_policy_document" "remediate_iam_key" {
  statement {
    # IAM アクセスキーの無効化に必要な最小権限。
    # iam:CreateAccessKey / iam:DeleteAccessKey は含めない（職務分離）。
    sid       = "DisableIAMKey"
    effect    = "Allow"
    actions   = ["iam:UpdateAccessKey", "iam:ListAccessKeys"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-remediate-iam-key:*"]
  }

  statement {
    sid       = "AllowSNSPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.remediation_alerts.arn]
  }
}

resource "aws_iam_role" "remediate_iam_key" {
  name               = "${var.project_name}-remediate-iam-key-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-remediate-iam-key-role"
  }
}

resource "aws_iam_role_policy" "remediate_iam_key" {
  name   = "${var.project_name}-remediate-iam-key-policy"
  role   = aws_iam_role.remediate_iam_key.id
  policy = data.aws_iam_policy_document.remediate_iam_key.json
}

# ---
# EC2 隔離 Lambda 用ロール
# ---

data "aws_iam_policy_document" "isolate_ec2" {
  statement {
    # EC2 隔離（セキュリティグループ差し替え）に必要な最小権限。
    # ec2:TerminateInstances は含めない。隔離と終了は別の決定プロセスで行う（SCS 頻出の設計思想）。
    # ec2:RevokeSecurityGroupEgress: 隔離 SG 作成時にデフォルトのアウトバウンド全許可を削除するために必要。
    sid    = "IsolateEC2"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeSecurityGroups",
      "ec2:CreateSecurityGroup",
      "ec2:ModifyInstanceAttribute",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-isolate-ec2:*"]
  }

  statement {
    sid       = "AllowSNSPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.remediation_alerts.arn]
  }
}

resource "aws_iam_role" "isolate_ec2" {
  name               = "${var.project_name}-isolate-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-isolate-ec2-role"
  }
}

resource "aws_iam_role_policy" "isolate_ec2" {
  name   = "${var.project_name}-isolate-ec2-policy"
  role   = aws_iam_role.isolate_ec2.id
  policy = data.aws_iam_policy_document.isolate_ec2.json
}
