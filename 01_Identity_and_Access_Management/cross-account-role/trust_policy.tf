# =============================================================================
# trust_policy.tf — cross-account-role
# peer アカウント側：クロスアカウントロールと信頼ポリシーの定義。
#
# 【クロスアカウントアクセスの2段階制御】
# クロスアカウントアクセスには「両方」が必要（AND 条件）：
#   1. peer 側の信頼ポリシー：「learner アカウントの誰かを信頼する」（このファイル）
#   2. learner 側のアイデンティティポリシー：「この caller に AssumeRole を許可する」
#      ※ このモジュールでは OrganizationAccountAccessRole（learner-admin プロファイル）が
#         既に admin 権限を持つため、アイデンティティポリシーの追加作成は不要。
# SCS頻出：「どちらか一方だけでは AssumeRole できない」
#
# 【前提条件】
# 00_Baseline が apply 済みであること。
# learner_account_id / peer_account_id を terraform.tfvars に設定する。
#
#   cd ../../00_Baseline
#   terraform output learner_account_id
#   terraform output peer_account_id
#
# 【確認ポイント（terraform apply 後）】
# 1. peer アカウントの cross-account ロールを引き受ける
#    aws sts assume-role \
#      --role-arn <cross_account_role_arn> \
#      --role-session-name cross-account-test \
#      --profile learner-admin
# 2. 取得した一時認証情報を環境変数にセットする
#    export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=...
# 3. peer アカウントのリソースを ReadOnly 参照できることを確認する
#    aws sts get-caller-identity   # peer アカウントの account ID が表示される
#    aws s3 ls
# 4. terraform destroy でクリーンアップ
#
# ※ 繰り返し検証する場合は ~/.aws/config に named profile を設定すると
#    --profile cross-account-peer 一発で済む。
#    [profile cross-account-peer]
#      role_arn       = <cross_account_role_arn>
#      source_profile = learner-admin
# =============================================================================

# ---
# クロスアカウントロール（peer アカウント側）
# ---

# peer アカウントに作成するクロスアカウントアクセス用ロール。
resource "aws_iam_role" "cross_account" {
  provider = aws.peer

  name               = "${var.project_name}-cross-account-role"
  assume_role_policy = data.aws_iam_policy_document.cross_account_trust.json

  tags = {
    Name = "${var.project_name}-cross-account-role"
  }
}

# このロールで「できること」：peer アカウントの ReadOnly 参照。
# ハンズオンの目的は信頼ポリシーの仕組みを理解することであり、
# 付与する権限自体は ReadOnlyAccess で十分。
resource "aws_iam_role_policy_attachment" "cross_account_readonly" {
  provider = aws.peer

  role       = aws_iam_role.cross_account.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ---
# 信頼ポリシー
# ---

# learner アカウントのルートを信頼元にする。
# ルートを信頼元にすることで「peer 側は誰でも OK」とし、
# 「誰が引き受けられるか」の制御を learner 側のアイデンティティポリシーに委ねる。
# これが2段階制御の核心。
data "aws_iam_policy_document" "cross_account_trust" {
  statement {
    sid     = "AllowLearnerAccountAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.learner_account_id}:root"]
    }

    # ExternalId：サードパーティ連携時に必須のセキュリティ対策。
    # 悪意ある第三者が別の顧客の信頼ポリシーを悪用して AssumeRole する
    # 「混乱した使節（Confused Deputy）攻撃」を防ぐ。
    # ハンズオンでは学習目的でコメントアウトするが、本番では必ず設定すること。
    # condition {
    #   test     = "StringEquals"
    #   variable = "sts:ExternalId"
    #   values   = ["<unique-external-id>"]
    # }
  }
}
