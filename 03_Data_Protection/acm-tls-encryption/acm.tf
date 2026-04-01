# =============================================================================
# acm.tf — acm-tls-encryption
# tls プロバイダで自己署名証明書を生成し、ACM にインポートする。
# Route 53 / ドメイン取得なしで ALB の HTTPS を動作させるための最小構成。
#
# 【ACM マネージド証明書 vs インポート証明書の違い（SCS 頻出）】
#
# | 機能                        | マネージド（DNS/メール検証）  | インポート（自己署名等）      |
# |-----------------------------|-------------------------------|-------------------------------|
# | 自動更新                    | あり（有効期限 60 日前）      | なし（手動のみ）              |
# | ACM の有効期限アラート      | あり（EventBridge 経由）      | 発火しない                    |
# | CloudWatch 証明書メトリクス | あり                          | なし                          |
# | ドメイン所有証明が必要      | 必要                          | 不要                          |
# | CA                          | Amazon Trust Services         | 任意（今回は自己署名）        |
#
# インポート証明書の監視は ACM に任せられない。
# 代替手段：EventBridge Scheduler + SNS で残日数を定期チェックするカスタム実装が必要。
# 本番でインポート証明書を使う場合は必ずこの監視設計を検討すること。
#
# 【このモジュールで validity_period_hours = 1 にする理由】
# 1. apply から 1 時間後にブラウザで「証明書の有効期限切れ」警告が表示される
#    → HTTPS 通信自体は成立する（ALB は有効期限切れの証明書でも使用できる）
# 2. ACM の有効期限アラートが発火しないことを確認できる
#    → インポート証明書に対して ACM は有効期限監視を行わないことの証明
#
# 【セキュリティ上の注意】
# tls_private_key リソースの秘密鍵は terraform.tfstate に平文で保存される。
# ハンズオン用途では許容範囲だが、本番環境での使用は避けること。
#
# 【確認ポイント】
# ブラウザで https://<ALB_DNS_NAME> にアクセスする（ALB_DNS は terraform output -raw alb_dns_name で確認）。
#
# apply 直後:
# → 「この接続ではプライバシーが保護されません」（自己署名のため CA が信頼されない）
#
# 1 時間経過後:
# → 「証明書の有効期限が切れています」（validity_period_hours = 1 で失効）
# → HTTPS 通信自体は成立する（ALB は有効期限切れの証明書でも配信し続ける）
# → ACM からの有効期限アラートは来ない（インポート証明書は ACM の監視対象外）
# =============================================================================

# TLS プライベートキーを生成する。
# RSA 2048 ビット：ACM インポートの最小要件を満たし、
# ALB の TLS ポリシーが要求する暗号スイートとも互換性がある。
resource "tls_private_key" "self_signed" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# 自己署名証明書を生成する。
# validity_period_hours = 1 で apply 後 1 時間以内に有効期限切れになる。
# → ブラウザで「証明書の有効期限切れ」警告が表示されること、
#   および ACM がアラートを発しないことの両方をハンズオンで確認できる。
resource "tls_self_signed_cert" "self_signed" {
  private_key_pem = tls_private_key.self_signed.private_key_pem

  # CN（Common Name）はドメイン名として任意の文字列を指定できる（自己署名のため検証なし）。
  # ".local" サフィックスで「公開ドメインではない」ことを明示する。
  subject {
    common_name = "${var.project_name}.local"
  }

  # 1 時間で失効させる。
  # 本番環境での ACM マネージド証明書は 13 ヶ月（395 日）で自動更新される。
  validity_period_hours = 1

  # ALB の HTTPS リスナーに割り当てるためにはサーバー認証用途（TLS Web Server Authentication）の
  # 拡張鍵使用（EKU）が必要。ACM のインポート検証でも確認される要件。
  allowed_uses = [
    "key_encipherment",  # RSA 鍵交換で使用
    "digital_signature", # TLS ハンドシェイクの署名
    "server_auth",       # TLS Web Server Authentication（ALB に必須）
  ]
}

# 自己署名証明書を ACM にインポートする。
# インポートモード（certificate_body + private_key）は
# リクエストモード（domain_name + validation_method）とは排他的。
#
# インポートされた証明書は即座に ISSUED 状態になる（DNS/メール検証の待機が不要）。
# そのため ALB HTTPS リスナー側で depends_on による待機は不要。
#
# lifecycle.create_before_destroy：
# terraform destroy & re-apply 時に新しい証明書が先に ACM に登録されてから
# 古い証明書が削除される順序を保証する（ALB リスナーの CertificateNotFoundException 防止）。
resource "aws_acm_certificate" "main" {
  certificate_body = tls_self_signed_cert.self_signed.cert_pem
  private_key      = tls_private_key.self_signed.private_key_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cert"
  }
}
