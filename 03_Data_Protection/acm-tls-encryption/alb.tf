# =============================================================================
# alb.tf — acm-tls-encryption
# ALB の定義。HTTP→HTTPS 301 リダイレクトと HTTPS TLS 終端を実装する。
#
# 【HTTP→HTTPS リダイレクトの仕組み】
# ポート 80 リスナーに redirect アクション（status_code = "HTTP_301"）を設定する。
# 301（永続）vs 302（一時）の違い：
#   - 301: ブラウザがリダイレクト先をキャッシュする → 次回以降 HTTP リクエスト不要
#   - 302: キャッシュしない → 毎回 HTTP でアクセスして 302 を受け取る
# SCS 試験では「永続リダイレクト = 301」「一時リダイレクト = 302」が問われる。
#
# 【TLS ポリシーの選択基準（SCS 頻出）】
# ELBSecurityPolicy-TLS13-1-2-2021-06（このモジュールで使用）:
#   - TLS 1.3 + TLS 1.2 をサポート（TLS 1.0/1.1 は無効）
#   - 強力な暗号スイートのみ（ECDHE + AES-GCM / CHACHA20）
#   - セキュリティ優先構成。古いクライアント（IE 10、Android 4.x 等）は接続不可
#
# ELBSecurityPolicy-TLS-1-2-Ext-2018-06（旧来のポリシー例）:
#   - TLS 1.2 のみ（TLS 1.3 なし）
#   - 弱い暗号スイートも含む → 古いクライアントとの互換性は高い
#   - 「互換性優先」が必要な場合に選択する
#
# → SCS 試験の判断基準：「最新のみ対応でよい = TLS13-1-2-2021-06」「古いクライアントを含む = 旧ポリシー」
#
# 【インポート証明書で depends_on が不要な理由】
# DNS/メール検証モードでは証明書が PENDING_VALIDATION → ISSUED に遷移するまで
# aws_acm_certificate_validation リソースで apply をブロックする必要があった。
# インポートモードでは aws_acm_certificate が作成された時点で即座に ISSUED 状態になる。
# そのため certificate_arn の参照（暗黙依存）だけで正しい順序が保証される。
#
# 【確認ポイント】
# ALB_DNS=$(terraform output -raw alb_dns_name)
#
# HTTP→HTTPS リダイレクト確認:
# curl -I "http://${ALB_DNS}"
# → HTTP/1.1 301 Moved Permanently
#
# HTTPS 直接アクセス（-k で自己署名を無視）:
# curl -Ik "https://${ALB_DNS}"
# → HTTP/1.1 200 OK（HTTP と異なり 301 されず Lambda のレスポンスが直接返る）
# =============================================================================

# ALB セキュリティグループ。
# インターネットからの HTTP(80) と HTTPS(443) を許可する。
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb"
  description = "ALB: allow HTTP and HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# インターネットからの HTTP アクセスを許可する（リダイレクト用）。
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# インターネットからの HTTPS アクセスを許可する（TLS 終端用）。
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ALB からのアウトバウンドをすべて許可する。
# Lambda ターゲットグループへの呼び出しは AWS 内部通信のため実質的には不要だが、
# セキュリティグループのデフォルト動作（egress なし = 全拒否）を上書きする。
resource "aws_vpc_security_group_egress_rule" "alb_all_out" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Application Load Balancer。
# internet-facing = インターネット向けの公開 ALB。
# 本番環境ではアクセスログ（access_logs）の S3 バケットへの出力を有効化することを推奨。
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# HTTP リスナー（ポート 80）。
# forward ではなく redirect アクションで HTTPS への 301 永続リダイレクトを返す。
# #{host}, #{path}, #{query} は ALB のビルトイン変数でリクエストの各部分を引き継ぐ。
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      status_code = "HTTP_301" # 永続リダイレクト（ブラウザキャッシュ対象）
      protocol    = "HTTPS"
      port        = "443"
      host        = "#{host}"
      path        = "/#{path}"
      query       = "#{query}"
    }
  }
}

# HTTPS リスナー（ポート 443）。
# TLS 1.3 + TLS 1.2 のみを許可するセキュリティ優先ポリシーを使用する。
# インポートモードの証明書は作成時点で即 ISSUED になるため、
# depends_on による待機は不要。certificate_arn の参照（暗黙依存）で十分。
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"

  # TLS 1.3 + TLS 1.2 のみ許可。TLS 1.0/1.1 と弱い暗号スイートを排除したセキュリティ優先構成。
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }
}
