# =============================================================================
# scp_region_guardrail.tf — organizations-scp
# ap-northeast-1（東京）以外のリージョンへのリソース作成を禁止する SCP。
#
# 【なぜリージョンを制限するか】
# 意図しないリージョンへのリソース作成を防ぎ、データレジデンシー要件への準拠と
# コスト管理・セキュリティ監視の範囲を限定する。
# SCS頻出：「特定リージョン以外での操作を SCP でガードレール」
#
# 【グローバルサービスの除外について】
# IAM / STS / CloudFront / Route 53 / Support などはリージョン指定なしで動作する
# グローバルサービスであり、aws:RequestedRegion 条件の対象外になる場合がある。
# ただし Terraform で明示的に NotAction で除外しておくことで、
# 意図しない拒否（Deny）によるオペレーション障害を防ぐ。
# =============================================================================

resource "aws_organizations_policy" "region_guardrail" {
  name        = "${var.project_name}-region-guardrail"
  description = "Deny resource creation outside ap-northeast-1 to enforce data residency"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ap-northeast-1 以外のリージョンへのリソース作成を Deny する。
        # aws:RequestedRegion 条件に StringNotEquals を使う。
        Sid    = "DenyNonTokyoRegion"
        Effect = "Deny"
        # NotAction を使ってグローバルサービスを除外する。
        # これらのサービスは「リージョン」の概念がないため、
        # Action = "*" + StringNotEquals だと誤って Deny してしまうケースがある。
        NotAction = [
          # IAM はグローバルサービス（リージョン指定なし）
          "iam:*",
          # STS の一部操作はグローバルエンドポイントを使用する
          "sts:*",
          # Organizations 管理操作はグローバル
          "organizations:*",
          # サポートセンターへのアクセス
          "support:*",
          # AWS Billing / Cost Explorer はグローバル
          "aws-portal:*",
          "budgets:*",
          "ce:*",
          # CloudFront はグローバルサービス
          "cloudfront:*",
          # Route 53 はグローバルサービス
          "route53:*",
          "route53domains:*",
          # WAF の一部（CloudFront 用）はグローバル
          "waf:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            # ap-northeast-1 以外のリージョンでのリクエストを Deny する。
            "aws:RequestedRegion" = "ap-northeast-1"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-region-guardrail"
  }
}

# SCP を対象 OU にアタッチする。
resource "aws_organizations_policy_attachment" "region_guardrail" {
  policy_id = aws_organizations_policy.region_guardrail.id
  target_id = var.target_ou_id
}
