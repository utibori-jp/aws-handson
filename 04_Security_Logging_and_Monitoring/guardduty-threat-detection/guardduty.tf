# =============================================================================
# guardduty.tf — guardduty-threat-detection
# Amazon GuardDuty を有効化し、アカウント内の脅威を継続的に検出する。
#
# 【GuardDuty とは】
# CloudTrail ログ・VPC Flow Logs・DNS ログを機械学習で分析し、
# 「振る舞いの異常」を検知するマネージドな脅威検知サービス。
# IAM Access Analyzer（リソースポリシーの静的解析）と対照的に、
# GuardDuty は「実際の操作・通信パターン」を動的に分析する（SCS 頻出の対比）。
#
# 【検出するフィンディングカテゴリ（代表例）】
# - UnauthorizedAccess：想定外の場所や時間帯からの API コール
# - Recon（偵察）：IAM ユーザー一覧取得など、攻撃の前段階となる操作
# - Backdoor：C2（Command & Control）サーバーへの通信
# - CryptoCurrency：クリプトマイニングに使われる IP への通信
# - Exfiltration：大量データの外部転送
#
# 【入力データソース】
# - CloudTrail 管理イベント：API コール（有効化は自動。無効化不可）
# - VPC Flow Logs：ネットワーク通信パターン（VPC があれば自動収集）
# - DNS ログ：Route 53 経由の DNS クエリ（自動収集）
# - S3 データイベント：オプション（このモジュールでは有効化しない）
# =============================================================================

resource "aws_guardduty_detector" "main" {
  # GuardDuty を有効化する。
  # 無効化（enable = false）にするとフィンディングは保持されるが検出は停止する。
  enable = true

  # フィンディングの発行頻度。
  # FIFTEEN_MINUTES: 15 分ごと（ハンズオンで体験しやすい最短値）
  # ONE_HOUR: 1 時間ごと / SIX_HOURS: 6 時間ごと（デフォルト）
  # 本番環境では SIX_HOURS で十分な場合が多い（高頻度は CloudWatch イベント量が増える）。
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "${var.project_name}-guardduty"
  }
}
