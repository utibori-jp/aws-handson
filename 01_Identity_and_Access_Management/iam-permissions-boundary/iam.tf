# =============================================================================
# iam.tf — iam-permissions-boundary
# 権限境界（Permissions Boundary）を使った「最大権限の上限設定」の実証。
#
# 【権限境界とは】
# IAM エンティティ（ユーザー/ロール）に付与できる「最大権限の上限」を定義するポリシー。
# 実際の有効権限 = アイデンティティポリシー ∩ 権限境界 となる。
#
# 【このモジュールで学ぶこと】
# - 開発者が自分の権限を昇格させる「権限昇格攻撃」を防ぐ仕組み
# - SCS頻出：「最小権限原則をエンフォースする管理的コントロール」
#
# 【検証方法】
# ─ メイン（00_Baseline の learner アカウントを使う場合）──────────────────
# 1. variables.tf のコメントを参考に sso_instance_arn と
#    learner_admin_permission_set_arn を terraform.tfvars に設定する
# 2. learner-admin SSO プロファイルを使って apply する
#      terraform apply -var aws_profile=learner-admin
# 3. IAM Identity Center の learner-admin でサインインし、以下を試す
#
#    ① AdministratorAccess が付いているのに IAM 操作が拒否されることを確認
#       aws iam create-policy --policy-name test-escalation \
#         --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}'
#       # → AccessDenied が返れば境界が正しく機能している
#
#    ② EC2/S3 操作は通ることを確認（境界内の操作はブロックされない）
#       aws ec2 describe-instances
#       aws s3 ls
#
# ─ フォールバック（learner アカウントなし）─────────────────────────────────
# SSO 変数を指定しなければ PermissionSet アタッチはスキップされる。
# 代わりに developer ロール（terraform-sso と同一アカウント）が作成されるので、
# terraform-sso の認証情報から AssumeRole して同様の検証ができる。
#
#   ROLE_ARN=$(terraform output -raw developer_role_arn)
#   aws sts assume-role --role-arn $ROLE_ARN --role-session-name test \
#     --query 'Credentials' --output json
#   # → 取得した一時クレデンシャルを export してから上記の aws iam create-policy を試す
# =============================================================================

locals {
  sso_configured = (
    var.sso_instance_arn != null && var.learner_admin_permission_set_arn != null
  )
}

# ---
# 権限境界ポリシー
# ---

# 開発者に許可する操作の「上限」を定義する。
# このポリシーが境界として設定されたエンティティは、ここに列挙した操作しか実行できない。
# アイデンティティポリシーでより広い権限（AdministratorAccess 等）を付与しても、
# 境界を超えた操作は拒否される。
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
        #   1. 新しいポリシーを作成してロール/ユーザー/グループにアタッチする
        #      → CreatePolicy + AttachRolePolicy / AttachUserPolicy / AttachGroupPolicy
        #   2. 既存ポリシーに新バージョンを追加して権限を昇格する
        #      → CreatePolicyVersion（新バージョン作成）+ SetDefaultPolicyVersion（デフォルト切り替え）
        #      ※ SetDefaultPolicyVersion 単体でも、過去に作成済みの広い権限バージョンに戻せる
        #   3. インラインポリシーを直接書き込んで権限を昇格する
        #      → PutRolePolicy / PutUserPolicy / PutGroupPolicy
        #      ※ CreatePolicy を経由しないため、1 の防御をすり抜ける別経路
        #   4. 権限境界そのものを削除して制約を外す
        #      → DeleteRolePermissionsBoundary / DeleteUserPermissionsBoundary
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
# メイン: learner-admin PermissionSet への境界アタッチ
# ---

# AdministratorAccess を持つ learner-admin PermissionSet に境界を設定することで、
# 「Admin 権限を持っていても IAM 昇格操作はできない」という
# 権限境界の効果を直接体感できる。
#
# sso_instance_arn / learner_admin_permission_set_arn が未指定の場合はスキップする。
# その場合は下記の developer ロールを使ったフォールバック検証を参照。
resource "aws_ssoadmin_permissions_boundary_attachment" "learner_admin" {
  count = local.sso_configured ? 1 : 0

  instance_arn       = var.sso_instance_arn
  permission_set_arn = var.learner_admin_permission_set_arn

  permissions_boundary {
    # カスタマー管理ポリシーは ARN ではなく name + path で参照する。
    customer_managed_policy_reference {
      name = aws_iam_policy.developer_boundary.name
      path = "/"
    }
  }
}

# ---
# フォールバック: developer ロール（learner アカウント不使用時）
# ---

# learner アカウントなしで検証したい場合に使用する。
# trust policy は同一アカウントのルートを信頼するため、
# terraform-sso の認証情報から直接 AssumeRole できる。
data "aws_iam_policy_document" "developer_assume_role" {
  statement {
    sid     = "AllowSameAccountAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      # アカウント全体を信頼元にする（ルート ARN）。
      # ソースアカウント側でアイデンティティポリシーにより「誰が引き受けられるか」を制御する。
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "developer" {
  name               = "${var.project_name}-developer"
  assume_role_policy = data.aws_iam_policy_document.developer_assume_role.json

  # 権限境界を設定する。
  # この1行が「このロールの有効権限 = PowerUserAccess ∩ developer_boundary」を保証する。
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
resource "aws_iam_role_policy_attachment" "developer_poweruser" {
  role       = aws_iam_role.developer.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
