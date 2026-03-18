# =============================================================================
# iam.tf — iam-permissions-boundary
# 権限境界（Permissions Boundary）を使った開発者ロールの作成。
#
# 【権限境界とは】
# IAM エンティティ（ユーザー/ロール）に付与できる「最大権限の上限」を定義するポリシー。
# 実際の有効権限 = アイデンティティポリシー ∩ 権限境界 となる。
#
# 【このモジュールで学ぶこと】
# - 開発者が自分の権限を昇格させる「権限昇格攻撃」を防ぐ仕組み
# - SCS頻出：「最小権限原則をエンフォースする管理的コントロール」
#
# 【確認ポイント（apply 後）】
# 1. developer ロールに PowerUserAccess が付与されていることをコンソールで確認する
# 2. 権限境界ポリシーの JSON を読み、「有効権限 = 境界 ∩ アイデンティティポリシー」を確認する
# 3. 00_Baseline の learner ユーザーで developer ロールに AssumeRole し、
#    IAM 操作（CreatePolicy など）が拒否されることを確認する
# =============================================================================

# ---
# 権限境界ポリシー
# ---

# 開発者に許可する操作の「上限」を定義する。
# このポリシーが境界として設定されたロールは、ここに列挙した操作しか実行できない。
# アイデンティティポリシーでより広い権限を付与しても、境界を超えた操作は拒否される。
# 加えて、アイデンティティーポリシー側のAllowも必須。
resource "aws_iam_policy" "developer_boundary" {
  name        = "${var.project_name}-developer-boundary"
  description = "Permissions boundary for developer roles — caps effective permissions to prevent privilege escalation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # EC2 の読み取りと限定的な操作のみ許可。
        # セキュリティグループの変更（ec2:AuthorizeSecurityGroupIngress など）は含めないことで、
        # 開発者がポートを意図せず開放することを防ぐ。
        # メモ：これAMIを作成しておいて、そのEC2作成OK→SG変更NG試せたら熱い
        Sid    = "AllowEC2Limited"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:RebootInstances"
        ]
        Resource = "*"
      },
      {
        # S3 の読み書きを許可。
        # バケットポリシーの変更（s3:PutBucketPolicy）は含めないことで、
        # 開発者がバケットを意図せず公開することを防ぐ。
        Sid    = "AllowS3Limited"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      },
      {
        # CloudWatch ログの読み取りを許可（デバッグ用途）。
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:Describe*",
          "logs:Get*",
          "logs:List*",
          "logs:FilterLogEvents"
        ]
        Resource = "*"
      },
      {
        # 【最重要】IAM 権限昇格操作を全面 Deny する。
        # Deny は Allow より優先されるため、アイデンティティポリシーで IAM を許可しても無効になる。
        #
        # 防いでいる攻撃パターン：
        #   - 新しいポリシーを作成してアタッチする（CreatePolicy + AttachRolePolicy）
        #   - 既存ポリシーを書き換えて権限を昇格する（CreatePolicyVersion）
        #   - 権限境界そのものを削除して制約を外す（DeleteRolePermissionsBoundary）
        # メモ：説明を省略してる攻撃パターンがあるのが気になる
        Sid    = "DenyIAMEscalation"
        Effect = "Deny"
        Action = [
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:AttachRolePolicy",
          "iam:AttachUserPolicy",
          "iam:AttachGroupPolicy",
          "iam:PutRolePolicy",
          "iam:PutUserPolicy",
          "iam:PutGroupPolicy",
          "iam:DeleteRolePermissionsBoundary",
          "iam:DeleteUserPermissionsBoundary"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-developer-boundary"
  }
}

# ---
# 開発者ロール（権限境界付き）
# ---

# 開発者ロールの信頼ポリシー。
# 同一アカウント内の IAM ユーザーが AssumeRole できるように設定する。
data "aws_iam_policy_document" "developer_assume_role" {
  statement {
    sid     = "AllowSameAccountAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      # アカウント全体を信頼元にする（ルート ARN）。
      # ソースアカウント側でアイデンティティポリシーにより「誰が引き受けられるか」を制御する。
      # この2段階制御がクロスアカウントにも応用できる（cross-account-role モジュール参照）。
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "developer" {
  name               = "${var.project_name}-developer"
  assume_role_policy = data.aws_iam_policy_document.developer_assume_role.json

  # 権限境界を設定する。
  # この1行が「このロールの有効権限 = PowerUserAccess ∩ developer_boundary」を保証する。
  # 管理者（Terraform 実行者）が境界を設定するため、
  # 開発者自身がロールから境界を外すことはできない（DenyIAMEscalation で保護）。
  permissions_boundary = aws_iam_policy.developer_boundary.arn

  tags = {
    Name = "${var.project_name}-developer"
  }
}

# 開発者ロールのアイデンティティポリシー（広い権限）。
# PowerUserAccess は IAM 以外のほぼ全操作を許可する広いポリシーだが、
# 権限境界によって有効権限は EC2/S3/CloudWatch Logs の限定操作に絞られる。
# 「広いアイデンティティポリシー + 厳しい境界」という組み合わせは、
# 境界を一元管理したい大規模組織でよく使われるパターン。
# メモ：Terraform-ssoからAssumeRole→禁止されてる動作とされてない動作を両方試すとか面白そう。
resource "aws_iam_role_policy_attachment" "developer_poweruser" {
  role       = aws_iam_role.developer.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
