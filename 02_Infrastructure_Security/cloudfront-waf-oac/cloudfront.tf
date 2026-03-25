# =============================================================================
# cloudfront.tf — cloudfront-waf-oac
# CloudFront Distribution + OAC + レスポンスヘッダーポリシーの定義。
#
# 【レスポンスヘッダーポリシーとは】
# CloudFront がレスポンスに付与する HTTP ヘッダーを一元管理するポリシー。
# セキュリティヘッダーを CloudFront レベルで強制付与することで、
# オリジン（S3）側の設定に依存せずにブラウザのセキュリティ機能を有効化できる。
# SCS頻出：「HSTS・CSP・X-Frame-Options によるエッジ防御」
#
# 【確認ポイント】
# CloudFront 経由でコンテンツが取得でき、セキュリティヘッダーが付与されていることを確認する。
#
#   DOMAIN=$(terraform output -raw cloudfront_domain_name)
#   curl -si "https://${DOMAIN}/index.html" | grep -E "HTTP|strict-transport|x-frame|x-content"
#   # → HTTP/2 200
#   # → strict-transport-security: max-age=31536000
#   # → x-frame-options: DENY
#   # → x-content-type-options: nosniff
# =============================================================================

# ---
# Origin Access Control
# ---

# OAC を定義する（OAI の後継）。
# CloudFront が S3 へリクエストする際に SigV4 で署名するための設定。
#
# 【署名の意義】
# S3 バケットポリシーは Principal = cloudfront.amazonaws.com に限定しているが、
# 署名がなければ「どの CloudFront からのリクエストか」を S3 が識別できない。
# 攻撃者が別の CloudFront ディストリビューションを立てても、
# s3.tf の aws:SourceArn 条件が「このディストリビューション以外」を拒否するため無効。
# 署名は S3 が aws:SourceArn 条件を評価する前提となる認証手段。
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for ${var.project_name} S3 origin"
  origin_access_control_origin_type = "s3"

  # always: 全てのリクエストに署名を付与する（推奨設定）。
  # no-override: オリジンが Authorization ヘッダーを持つ場合はオーバーライドしない。
  signing_behavior = "always"

  # SigV4 は AWS の標準認証プロトコル。
  signing_protocol = "sigv4"
}

# ---
# レスポンスヘッダーポリシー（セキュリティヘッダー）
# ---

# S3 などのオリジン側で個別に設定が難しいセキュリティヘッダーを、エッジ（CloudFront）で一括付与する。
# これにより、オリジンの実装に依存せず、ブラウザ側での脆弱性攻撃を境界レベルで防御できる。
# インフラ側の OAC 制御と、このブラウザ側のヘッダー制御を組み合わせることで多層防御を実現している。
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name    = "${var.project_name}-security-headers"
  comment = "Security headers for SCS study — HSTS, CSP, X-Frame-Options, etc."

  security_headers_config {
    # HSTS: ブラウザに「このドメインは常に HTTPS で接続せよ」と指示する。
    # max_age_sec = 31536000 は1年間。includeSubdomains は本番では慎重に設定すること。
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      override                   = true
    }

    # X-Content-Type-Options: MIME タイプスニッフィングを無効化する。
    # ブラウザが Content-Type を無視してファイルを実行しようとするのを防ぐ。
    content_type_options {
      override = true
    }

    # X-Frame-Options: クリックジャッキング攻撃を防ぐ。
    # DENY: いかなるフレームにも表示させない。
    frame_options {
      frame_option = "DENY"
      override     = true
    }

    # X-XSS-Protection: 古いブラウザ向けの XSS フィルタを有効化する。
    # 現代のブラウザは CSP で対応するが、後方互換のために設定する。
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }

    # Referrer-Policy: リファラー情報の送信範囲を制限する。
    # same-origin: 同一オリジン内のナビゲーション時のみリファラーを送信する。
    referrer_policy {
      referrer_policy = "same-origin"
      override        = true
    }
  }
}

# ---
# CloudFront Distribution
# ---

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.project_name} distribution with OAC and WAF"

  # WAF Web ACL のアタッチ（waf.tf で作成したリソースの ARN を参照）。
  # WAF は us-east-1 で作成されるが、CloudFront はグローバルなので問題ない。
  web_acl_id = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_id   = "s3-${aws_s3_bucket.origin.id}"

    # OAC を使うことで S3 直接アクセスを拒否し、CloudFront 経由のみ許可する。
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.origin.id}"
    viewer_protocol_policy = "redirect-to-https"

    # セキュリティヘッダーポリシーをアタッチする。
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # TTL の設定。ハンズオン用に短めに設定して動作確認しやすくする。
    min_ttl     = 0
    default_ttl = 60
    max_ttl     = 300
  }

  restrictions {
    geo_restriction {
      # 地理的制限なし（ハンズオン用）。
      # 本番で特定国からのアクセスを制限する場合は whitelist / blacklist を使う。
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # デフォルト証明書（*.cloudfront.net ドメイン用）を使用する。
    # カスタムドメインを使う場合は ACM 証明書を設定する（03章で扱う予定）。
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project_name}-distribution"
  }
}
