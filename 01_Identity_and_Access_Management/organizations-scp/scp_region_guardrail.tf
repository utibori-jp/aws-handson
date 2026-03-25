# =============================================================================
# scp_region_guardrail.tf — organizations-scp
# ap-northeast-1（東京）以外のリージョンへのリソース作成を禁止する SCP。
#
# 【SCS頻出ユースケース 2パターンの位置付け】
# このモジュールは以下の 2 つのガードレール SCP を実装する（実務ではさらに多くの SCP を組み合わせる）。：
#   1. ルート制限 (scp_root_restriction.tf)
#      → ルートユーザーの技術的エンフォース。IAM では制限できない領域をカバー。
#   2. リージョン制限 (このファイル)
#      → データレジデンシー・コスト管理・監視範囲の限定。
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
#
# 【確認ポイント】
# learner-admin プロファイルで us-east-1 に S3 バケット作成を試みる。
# SCP が適用されていれば AccessDenied になることを確認できる。
#
#   aws s3api create-bucket \
#     --bucket test-region-guardrail-$(date +%s) \
#     --region us-east-1 \
#     --create-bucket-configuration LocationConstraint=us-east-1 \
#     --profile learner-admin
#   # → An error occurred (AccessDenied) が返れば OK
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
          # WAF Classic と WAFv2 は別物として扱われる
          # このハンズオンでは WAFv2 を利用する
          "wafv2:*",
          "shield:*",
          # グローバルサービスのログを見るために除外設定が必要
          "cloudwatch:*",
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

# SCP を対象 OU（または Org ルート）にアタッチする。
# target_id は local.target_id（main.tf）で解決する。
resource "aws_organizations_policy_attachment" "region_guardrail" {
  policy_id = aws_organizations_policy.region_guardrail.id
  target_id = local.target_id
}
