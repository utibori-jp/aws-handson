# =============================================================================
# securityhub.tf — config-securityhub
# AWS Security Hub を有効化し、Config・IAM Access Analyzer のフィンディングを集約する。
#
# 【この章での Security Hub の役割】
# 4章（Security Logging and Monitoring）では Security Hub を「コンプライアンス評価・
# ポスチャ可視化」の役割で使う。Config ルールの評価結果や IAM Access Analyzer の
# 外部アクセス検知を ASFF で正規化し、セキュリティスコアとして可視化する。
#
# GuardDuty（脅威検知）との連携は 5章（Threat Detection and Incident Response）で扱う。
# 5章で GuardDuty を有効化すると、このモジュールで構築した Security Hub に
# GuardDuty フィンディングが自動的に流れ込んでくる。
#
# 【Security Hub とは】
# GuardDuty・Config・IAM Access Analyzer などのフィンディングを
# ASFF（Amazon Security Finding Format）という統一フォーマットで正規化・集約するサービス。
# 「セキュリティの一元的な可視性」を提供する（SCS 頻出）。
#
# 【ASFF とは】
# AWS Security Finding Format。各セキュリティサービスが異なるフォーマットで
# 検出結果を出力する問題を解決するための標準 JSON スキーマ。
# フィールド例：ProductArn / GeneratorId / Severity.Label / Remediation.Recommendation
# すべてのフィンディングが同じスキーマで扱えるため、自動化処理（EventBridge → Lambda）が容易になる。
#
# 【Standards（スタンダード）とは】
# Security Hub が評価するセキュリティベストプラクティスのセット。
# - AWS Foundational Security Best Practices（FSBP）: AWS が提供する独自ベストプラクティス
# - CIS AWS Foundations Benchmark 1.2.0: 業界標準のセキュリティ評価基準
# スタンダードに基づいて「セキュリティスコア（0〜100%）」が算出される（SCS 頻出）。
#
# 【Config / Security Hub の役割対比（SCS 頻出）】
# - Config:        設定評価（リソースの静的状態）→ "どういう設定状態か"
# - Security Hub:  上記の集約・正規化・スコアリング → "全体として安全か"
#
# 【⚠️ アカウント単位の制約】
# Security Hub はリージョンごとに1つのみ有効化できる。
# 5章のモジュールも Security Hub を利用するため、両モジュールを同時に
# apply した状態にすることはできない。5章を始める前に destroy すること。
# =============================================================================

# Security Hub を有効化する。
# このリソース1つで現在のリージョンに Security Hub が有効になる。
resource "aws_securityhub_account" "main" {
  # コントロールの自動有効化。
  # FSBP スタンダードのコントロールを新規追加時に自動で有効化する。
  auto_enable_controls = true

  # デフォルトスタンダードの自動有効化は無効にして、明示的にサブスクリプションを管理する。
  enable_default_standards = false
}

# ---
# スタンダードのサブスクリプション
# ---

# AWS Foundational Security Best Practices（FSBP）スタンダード。
# AWS が推奨するセキュリティコントロールのセット。
# サブスクリプション後、各コントロールが自動で評価されセキュリティスコアが算出される。
resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:${local.partition}:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]
}

# CIS AWS Foundations Benchmark 1.2.0 スタンダード。
# cloudwatch-metric-alarm モジュールで実装した CIS アラームと同じ基準を
# Security Hub 上でもスコアとして評価できる。
resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:${local.partition}:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.2.0"

  depends_on = [aws_securityhub_account.main]
}

# ---
# 製品統合（Product Subscriptions）
# ---

# IAM Access Analyzer のフィンディングを Security Hub に取り込む。
# 01_IAM 章の iam-access-analyzer モジュールのフィンディングも集約できる。
resource "aws_securityhub_product_subscription" "access_analyzer" {
  product_arn = "arn:${local.partition}:securityhub:${var.region}::product/aws/access-analyzer"

  depends_on = [aws_securityhub_account.main]
}

# ---
# Finding Aggregator（マルチリージョン集約・発展）
# ---

# Finding Aggregator はすべてのリージョンのフィンディングを指定リージョンに集約する機能。
# 単一アカウントのハンズオンでは不要なため count = 0 がデフォルト。
# マルチリージョン・マルチアカウント構成への拡張時に var.enable_finding_aggregator = true にする。
#
# 【マルチアカウント集約の仕組み（SCS 頻出）】
# Organizations の管理アカウント → Security Hub 管理者アカウントを指定
# → メンバーアカウントの有効化 → Finding Aggregator で全リージョンを集約
# この構成により、全アカウント・全リージョンのセキュリティ状況を1画面で確認できる。
resource "aws_securityhub_finding_aggregator" "main" {
  count = var.enable_finding_aggregator ? 1 : 0

  # ALL_REGIONS: すべてのリージョンのフィンディングをこのリージョンに集約する。
  linking_mode = "ALL_REGIONS"

  depends_on = [aws_securityhub_account.main]
}
