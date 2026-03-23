# =============================================================================
# scp_root_restriction.tf — organizations-scp
# ルートユーザーによる操作を禁止する SCP。
#
# 【SCS頻出ユースケース 2パターンの位置付け】
# このモジュールは以下の 2 つのガードレール SCP を実装する（実務ではさらに多くの SCP を組み合わせる）。：
#   1. ルート制限 (scp_root_restriction.tf)
#      → ルートユーザーの技術的エンフォース。IAM では制限できない領域をカバー。
#   2. リージョン制限 (このファイル)
#      → データレジデンシー・コスト管理・監視範囲の限定。
#
# 【なぜルートユーザーを制限するか】
# ルートユーザーはアカウントのすべての権限を持ち、IAM ポリシーで制限できない。
# 侵害された場合の被害が最大になるため、組織ポリシーとして使用を禁止することが推奨される。
# SCS頻出：「Organizations SCP でルートユーザーの操作を技術的にエンフォース」
#
# 【SCP の特性】
# - SCP は「許可の上限（ガードレール）」であり、単体では何も許可しない
# - この Deny SCP が適用されたアカウント内では、ルートユーザーでも対象操作が実行できない
# - 管理アカウント自体には SCP は適用されない（管理アカウントのルートは制限されない）
#
# 【確認ポイント】
# メンバーアカウントにルートユーザーでコンソールログインし、
# IAM → セキュリティ認証情報 → アクセスキーの作成 を試みる。
# SCP が適用されていれば AccessDenied になることを確認できる。
# （CLI では直接ルートユーザーとして操作できないため、コンソールでの確認が必要）
#
# ※ 管理アカウントは SCP の適用対象外のため、この方法では検証できない。
#    SCP の動作確認は必ずメンバーアカウントで行うこと。
#
# ※ Organizations で払い出したメンバーアカウントはルートパスワードが未設定。
#    ログインするには、アカウント作成時のメールアドレス宛に届く案内、または
#    コンソールログイン画面の「パスワードを忘れた場合」からパスワードをリセットする必要がある。
#    （対象メールアドレス: var.learner_account_email に指定したアドレス）
# =============================================================================

resource "aws_organizations_policy" "deny_root_actions" {
  name        = "${var.project_name}-deny-root-actions"
  description = "Deny all actions performed by the root user to enforce root user restriction"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ルートユーザーによるほぼ全操作を Deny する。
        # aws:PrincipalArn 条件でルートユーザーを特定する。
        # ルートの ARN パターン: arn:aws:iam::<account-id>:root
        Sid      = "DenyRootUserActions"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          ArnLike = {
            # ワイルドカード（*）でどのアカウントのルートユーザーにも適用する。
            "aws:PrincipalArn" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-deny-root-actions"
  }
}

# SCP を対象 OU（または Org ルート）にアタッチする。
# OU 配下の全メンバーアカウントにこの SCP が適用される。
# target_id は local.target_id（main.tf）で解決する。
resource "aws_organizations_policy_attachment" "deny_root_actions" {
  policy_id = aws_organizations_policy.deny_root_actions.id
  target_id = local.target_id
}
