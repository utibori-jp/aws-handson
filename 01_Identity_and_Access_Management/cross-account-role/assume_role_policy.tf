# =============================================================================
# assume_role_policy.tf — cross-account-role
# ソースアカウント側：クロスアカウントロールを引き受けるための IAM ユーザーと権限。
#
# 【2段階認証モデル（trust_policy.tf と対になる）】
# クロスアカウントアクセスには以下の「両方」が必要：
#   1. ターゲット側の信頼ポリシー：「ソースアカウントの誰かを信頼する」
#   2. ソース側のアイデンティティポリシー：「この caller に AssumeRole を許可する」
# どちらか一方だけでは AssumeRole できない（AND 条件）。
# =============================================================================

# ソースアカウントに cross-account ロールを引き受ける専用ユーザーを作成する。
# このモジュールを自己完結させるため、ここでユーザーを作成する。
# 既存の learner ユーザー（00_Baseline）に権限を付与する場合は、
# data "aws_iam_user" で参照してポリシーをアタッチすることもできる。
resource "aws_iam_user" "cross_account_caller" {
  name = "${var.project_name}-cross-account-caller"

  # force_destroy = true により、アクセスキーが残っていても terraform destroy できる。
  force_destroy = true

  tags = {
    Name = "${var.project_name}-cross-account-caller"
  }
}

# ソースアカウントの caller が ターゲットアカウントの cross_account ロールを
# AssumeRole するために必要なポリシー。
resource "aws_iam_policy" "assume_cross_account" {
  name        = "${var.project_name}-assume-cross-account"
  description = "Allow assuming the cross-account role in the target account"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAssumeCrossAccountRole"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        # AssumeRole の Resource にはロールの ARN を指定する。
        # ワイルドカード（arn:aws:iam::*:role/*）は使わず特定の ARN を明示すること（最小権限原則）。
        Resource = aws_iam_role.cross_account.arn
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-assume-cross-account"
  }
}

resource "aws_iam_user_policy_attachment" "caller_assume_cross_account" {
  user       = aws_iam_user.cross_account_caller.name
  policy_arn = aws_iam_policy.assume_cross_account.arn
}
