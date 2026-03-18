# =============================================================================
# securityhub.tf — security-hub-aggregation
# AWS Security Hub を有効化し、GuardDuty / Config のフィンディングを一元集約する。
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
# 【GuardDuty / Config との違い（SCS 頻出の3サービス対比）】
# - GuardDuty: 振る舞い検知（ログの動的分析）→ "何が起きたか"
# - Config:    設定評価（リソースの静的状態）→ "どういう状態か"
# - Security Hub: 上記の集約・正規化・スコアリング → "全体として安全か"
# =============================================================================

# Security Hub を有効化する。
# このリソース1つで現在のリージョンに Security Hub が有効になる。
resource "aws_securityhub_account" "main" {
  # コントロールの自動有効化。
  # FSBP スタンダードのコントロールを新規追加時に自動で有効化する。
  # 本番環境ではすべてのコントロールを把握するために false にすることもある。
  auto_enable_controls = true

  # 新規に統合されたサービス（GuardDuty / Inspector など）を自動で有効化する。
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

  # Security Hub が有効化された後にサブスクリプションを作成する。
  depends_on = [aws_securityhub_account.main]
}

# CIS AWS Foundations Benchmark 1.2.0 スタンダード。
# cloudwatch-metric-alarm モジュールで実装した CIS アラームと同じ基準を
# Security Hub 上でも評価できる。
resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:${local.partition}:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.2.0"

  depends_on = [aws_securityhub_account.main]
}

# ---
# 製品統合（Product Subscriptions）
# ---

# GuardDuty のフィンディングを Security Hub に取り込む。
# これにより GuardDuty のフィンディングが ASFF 形式で Security Hub に表示される。
# guardduty-threat-detection モジュールを先に apply した場合に体験価値が上がる。
resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:${local.partition}:securityhub:${var.region}::product/aws/guardduty"

  depends_on = [aws_securityhub_account.main]
}

# IAM Access Analyzer のフィンディングを Security Hub に取り込む。
# iam-access-analyzer モジュール（01_IAM 章）のフィンディングも集約できる。
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
