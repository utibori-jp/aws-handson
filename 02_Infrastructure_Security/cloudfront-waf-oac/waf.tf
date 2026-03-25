# =============================================================================
# waf.tf — cloudfront-waf-oac
# CloudFront 用の WAF Web ACL を us-east-1 に作成する。
#
# 【なぜ us-east-1 か】
# CloudFront スコープの WAF Web ACL は us-east-1 にしか作成できない。
# provider = aws.us_east_1 を明示することで、このファイルのリソースは
# メインプロバイダ（ap-northeast-1）ではなく us-east-1 に作成される。
#
# 【WAF Managed Rule Groups とは】
# AWS が管理するルールセット。シグネチャの更新は AWS が自動で行うため、
# 運用コストを抑えながら最新の脅威に対応できる。
# SCS頻出：「マネージドルールグループの種類と適用シナリオ」
#
# 【追加したルール】
# - AWSManagedRulesCommonRuleSet: SQL injection, XSS, ファイルインクルージョンなど一般的な脅威
# - AWSManagedRulesKnownBadInputsRuleSet: 悪意あるリクエストパターン（Log4Shell など）
#
# 【確認ポイント】
# SQLi パターンを含むリクエストが WAF でブロック（403）されることを確認する。
#
#   DOMAIN=$(terraform output -raw cloudfront_domain_name)
#   curl -si "https://${DOMAIN}/index.html?id=1'+OR+'1'%3D'1" | head -3
#   # → HTTP/1.1 403 Forbidden
#
# 正常リクエストは通過することも合わせて確認する。
#   curl -si "https://${DOMAIN}/index.html" | head -3
#   # → HTTP/2 200
# =============================================================================

resource "aws_wafv2_web_acl" "cloudfront" {
  # CloudFront 用 WAF は us-east-1 プロバイダで作成する。
  provider = aws.us_east_1

  name  = "${var.project_name}-cloudfront-waf"
  scope = "CLOUDFRONT"

  # デフォルトアクション: ルールに一致しないリクエストは許可する。
  # Deny をデフォルトにすると意図しないブロックが発生しやすいため、
  # マネージドルールで明示的にブロックする構成にする。
  default_action {
    allow {}
  }

  # ---
  # AWSManagedRulesCommonRuleSet
  # SQL injection, XSS, リモートファイルインクルージョンなど一般的な Web 攻撃を遮断する。
  # ---
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      # none: ルールグループ内の各ルールのアクション（Block/Count）をそのまま使用する。
      # count に変更すると「ブロックせず記録のみ」になり、誤検知確認に使える。
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ---
  # AWSManagedRulesKnownBadInputsRuleSet
  # Log4Shell（CVE-2021-44228）などの既知の悪意あるリクエストパターンを遮断する。
  # ---
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-cloudfront-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-cloudfront-waf"
  }
}
