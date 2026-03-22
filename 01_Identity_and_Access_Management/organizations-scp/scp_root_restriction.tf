# =============================================================================
# scp_root_restriction.tf — organizations-scp
# ルートユーザーによる操作を禁止する SCP。
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
        Sid    = "DenyRootUserActions"
        Effect = "Deny"
        Action = "*"
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
