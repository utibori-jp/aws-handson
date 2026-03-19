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
# 【前提条件】
# 00_Baseline が apply 済みであること。
# sso_instance_arn / learner_admin_permission_set_arn を terraform.tfvars に設定する。
#
#   cd ../../00_Baseline
#   terraform output sso_instance_arn
#   terraform output learner_admin_permission_set_arn
#
# 【確認ポイント（apply 後）】
# 00_Baseline で設定した learner-admin プロファイルをそのまま使う。
#
# ① AdministratorAccess が付いているのに IAM 操作が拒否されることを確認
#   aws iam create-policy --policy-name test-escalation \
#     --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
#     --profile learner-admin
#   # → AccessDenied が返れば境界が正しく機能している
#
# ② EC2/S3 操作は通ることを確認（境界内の操作はブロックされない）
#   aws ec2 describe-instances --profile learner-admin
#   aws s3 ls --profile learner-admin
# =============================================================================

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
        # 【なぜ Deny が必要か】
        # 権限境界は IAM の"上限設定"であり、IAM 操作そのものは止めない。
        # 開発者が境界ポリシー自体を差し替え・削除できる状態では境界が自己破壊するため、
        # "境界を変更・削除する権限" を Deny することで初めて境界が堅牢になる。
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
# learner-admin PermissionSet への境界アタッチ
# ---

# AdministratorAccess を持つ learner-admin PermissionSet に境界を設定することで、
# 「Admin 権限を持っていても IAM 昇格操作はできない」という
# 権限境界の効果を直接体感できる。
resource "aws_ssoadmin_permissions_boundary_attachment" "learner_admin" {
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
