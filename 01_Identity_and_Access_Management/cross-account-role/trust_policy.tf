# =============================================================================
# trust_policy.tf — cross-account-role
# ターゲットアカウント側：クロスアカウントロールと信頼ポリシーの定義。
#
# 【信頼ポリシーとは】
# IAM ロールの「誰が AssumeRole できるか」を定義するポリシー。
# アイデンティティポリシー（「何ができるか」）とは別の概念。
#
# 【クロスアカウントアクセスのフロー】
# 1. ターゲットアカウントにロールを作成し、信頼ポリシーでソースアカウントを信頼する
# 2. ソースアカウントの caller が sts:AssumeRole API を呼び出す
# 3. STS が一時認証情報を発行する（デフォルト1時間、最大12時間有効）
# 4. 一時認証情報を使ってターゲットアカウントのリソースを操作する
# =============================================================================

# クロスアカウントアクセス用ロール（ターゲットアカウントに作成）。
resource "aws_iam_role" "cross_account" {
  provider = aws.target

  name               = "${var.project_name}-cross-account-role"
  assume_role_policy = data.aws_iam_policy_document.cross_account_trust.json

  tags = {
    Name = "${var.project_name}-cross-account-role"
  }
}

# このロールで「できること」：ターゲットアカウントの ReadOnly 参照。
# ハンズオンの目的は信頼ポリシーの仕組みを理解することであり、
# 付与する権限自体は ReadOnlyAccess で十分。
resource "aws_iam_role_policy_attachment" "cross_account_readonly" {
  provider = aws.target

  role       = aws_iam_role.cross_account.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 信頼ポリシー：ソースアカウントのルートを信頼する。
# ルートを信頼元にすることで「ターゲット側は誰でもOK」とし、
# 「誰が引き受けられるか」の制御をソースアカウント側のアイデンティティポリシーに委ねる。
# これが2段階制御（assume_role_policy.tf 参照）の核心。
data "aws_iam_policy_document" "cross_account_trust" {
  statement {
    sid     = "AllowSourceAccountAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      # ソースアカウントのルート ARN を信頼元にする。
      # 本番でサードパーティに AssumeRole を許可する場合は、
      # 下記の ExternalId 条件を有効化して「混乱した使節（Confused Deputy）攻撃」を防ぐこと。
      identifiers = ["arn:${local.partition}:iam::${local.source_account_id}:root"]
    }

    # ExternalId：サードパーティ連携時に必須のセキュリティ対策。
    # 悪意のある第三者が別の顧客の信頼ポリシーを悪用して AssumeRole することを防ぐ。
    # ハンズオンでは学習目的でコメントアウトするが、本番では必ず設定すること。
    # condition {
    #   test     = "StringEquals"
    #   variable = "sts:ExternalId"
    #   values   = ["<unique-external-id>"]
    # }
  }
}
