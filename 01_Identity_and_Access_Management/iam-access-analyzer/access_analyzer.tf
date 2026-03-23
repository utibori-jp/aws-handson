# =============================================================================
# access_analyzer.tf — iam-access-analyzer
# IAM Access Analyzer を使って「意図しない外部アクセス」を自動検出する。
#
# 【IAM Access Analyzer とは】
# リソースポリシー（S3 バケットポリシー、KMS キーポリシーなど）を自動的に解析し、
# 信頼ゾーン（アカウントまたは Organization）外からアクセス可能なリソースを検出する。
# SCS頻出：「どのリソースが外部に公開されているかを継続的に監視する仕組み」
#
# 【検出対象リソースタイプ】
# S3 バケット / KMS キー / IAM ロール / Lambda 関数 / SQS キュー /
# Secrets Manager シークレット / SNS トピック など
#
# 【アーカイブルールとは】
# 既知の・意図的な外部アクセスを「想定済み」として自動アーカイブする。
# 誤検知ノイズを減らし、本当に調査が必要な検出に集中できるようにする。
#
# 【00_Baseline との連携】
# CloudTrail を有効化しておくと、Access Analyzer のフィンディングが
# CloudTrail に記録されるため、検出履歴を追跡できる。
# =============================================================================

# ---
# IAM Access Analyzer（アカウントスコープ）
# ---

resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "${var.project_name}-account-analyzer"

  # ACCOUNT タイプ：同一アカウント内のリソースポリシーを解析し、
  # アカウント外部からアクセス可能なリソースを検出する。
  # ORGANIZATION タイプを使うと Organizations 全体を信頼ゾーンにできるが、
  # 本モジュールは learner メンバーアカウントで動くため ACCOUNT を使用する。
  type = "ACCOUNT"

  tags = {
    Name = "${var.project_name}-account-analyzer"
  }
}

# ---
# アーカイブルール
# ---

# 同一アカウント内のプリンシパルからのアクセスを「想定済み」としてアーカイブする。
# Access Analyzer はアカウント外部からのアクセスを検出するが、
# このルールにより自アカウントの ARN を含むフィンディングは通知対象から除外される。
# ハンズオン中に意図的に作成するポリシーによる誤検知を抑制する。
resource "aws_accessanalyzer_archive_rule" "same_account" {
  analyzer_name = aws_accessanalyzer_analyzer.account.analyzer_name
  rule_name     = "same-account-principal"

  # アーカイブ条件：アクセス元プリンシパルが自アカウントの ARN を含む場合。
  # contains は部分一致（サブストリングマッチ）。
  filter {
    criteria = "principal.AWS"
    contains  = [local.account_id]
  }
}
