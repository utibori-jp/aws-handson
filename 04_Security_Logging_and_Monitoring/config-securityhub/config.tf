# =============================================================================
# config.tf — config-securityhub
# AWS Config の設定レコーダー・配信チャネルを有効化する。
#
# 【AWS Config とは】
# アカウント内のリソースの「設定状態」を継続的に記録し、
# 設定変更の履歴を追跡して「コンプライアンスルール」に照らし合わせて評価するサービス。
# GuardDuty（振る舞い検知）と対照的に、Config は「設定の静的評価」を担う（SCS 頻出の対比）。
#
# 【3リソースの依存順序】
# AWS Config を有効化するには以下の順序が必要（depends_on で明示する）：
#   1. aws_config_configuration_recorder — 「何を記録するか」の設定
#   2. aws_config_delivery_channel       — 「どこに配信するか」の設定
#   3. aws_config_configuration_recorder_status — レコーダーの有効化
#
# レコーダーステータスは配信チャネルが存在しないと有効化できないため、
# この順序を守らないと "InsufficientDeliveryPolicyException" エラーが発生する。
#
# 【⚠️ 課金について】
# Config は記録したリソースの設定変更 1 件ごとに課金される（無料枠あり）。
# 学習後は terraform destroy でレコーダーを停止することを推奨する。
#
# 【確認ポイント】
# apply から数分後に評価結果が揃う。以下のコマンドで準拠状況を確認する。
#
# Conformance Pack 全体の準拠状況サマリーを確認する
# aws configservice describe-conformance-pack-compliance \
#   --conformance-pack-name "scs-handson-scs-security-checks" \
#   --profile learner-readonly \
#   --region ap-northeast-1 \
#   --query 'ConformancePackRuleComplianceList[*].{Rule: ConfigRuleName, Status: ComplianceType}' \
#   --output table
#
# 非準拠リソースの一覧を取得（ルール名は上記コマンドの Rule カラムで確認する）
# aws configservice get-compliance-details-by-config-rule \
#   --config-rule-name "<任意のルール名>" \
#   --compliance-types NON_COMPLIANT \ ## Statusでフィルタリングするため、他のステータスを確認したければ、ここを変更する。
#   --profile learner-readonly \
#   --region ap-northeast-1 \
#   --query 'EvaluationResults[*].{Resource: EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId, Type: EvaluationResultIdentifier.EvaluationResultQualifier.ResourceType}' \
#   --output table
# =============================================================================

# ---
# Config サービスロール
# ---

# Config が AWS リソースの設定を読み取り、S3 に配信するために必要な IAM ロール。
resource "aws_iam_role" "config" {
  name = "${var.project_name}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-config-role"
  }
}

# AWS 管理ポリシーの AWSConfigRole をアタッチする。
# S3 への ConfigHistory/ConfigSnapshot の書き込み、SNS 通知、リソース読み取りに必要な権限が含まれる。
resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# ---
# S3 バケット（Config スナップショット・履歴の保管先）
# ---

resource "aws_s3_bucket" "config" {
  bucket        = "${var.project_name}-config-logs"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-config-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Config が S3 バケットへ書き込むために必要なバケットポリシー。
data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${local.account_id}/Config/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket     = aws_s3_bucket.config.id
  depends_on = [aws_s3_bucket_public_access_block.config]

  policy = data.aws_iam_policy_document.config_bucket.json
}

# ---
# Step 1: 設定レコーダー
# ---

# 「何を記録するか」を定義するリソース。
# recording_group で記録対象のリソースタイプを指定する。
resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    # 全リソースタイプを記録する（Conformance Pack のルール評価に必要なリソースをカバーするため）。
    # コスト削減のため特定リソースに絞りたい場合は all_supported = false にして
    # resource_types リストに必要なものだけを列挙する。
    all_supported                 = true
    include_global_resource_types = true
  }
}

# ---
# Step 2: 配信チャネル
# ---

# 「どこに配信するか」を定義するリソース。
# レコーダーが先に存在する必要があるため depends_on を明示する。
resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-config-channel"
  s3_bucket_name = aws_s3_bucket.config.bucket

  depends_on = [
    aws_config_configuration_recorder.main,
    aws_s3_bucket_policy.config,
  ]
}

# ---
# Step 3: レコーダーの有効化
# ---

# レコーダーを「有効化」するリソース。
# 配信チャネルが存在しないと有効化できないため depends_on を明示する。
# この3ステップの順序が AWS Config セットアップのポイント（SCS 頻出）。
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# ---
# Conformance Pack
# ---

# 【Conformance Pack とは】
# 複数の Config ルールとそれに対する修復アクションをまとめた「パッケージ」。
# CloudFormation テンプレート形式（YAML/JSON）で定義し、
# アカウント単位または Organizations 全体に適用できる（SCS 頻出）。
#
# 【評価モード（SCS 頻出の対比）】
# - 変更時トリガー（ConfigurationItemChangeNotification）:
#     リソースの設定変更があったときに即時評価する。
# - 定期トリガー（ScheduledNotification）:
#     1h / 3h / 6h / 12h / 24h の間隔で定期的に評価する。
#   → 動的に変わらない設定（MFA 有効化、ルートの MFA など）は定期評価が向いている。
#
# 【template_body に CloudFormation YAML を渡す理由】
# Conformance Pack は AWS 内部で CloudFormation スタックとして実装されている。
# Terraform はテンプレートをそのまま AWS Config API に渡し、
# AWS 側が CloudFormation スタックを作成して Config ルールをデプロイする。
# テンプレート本体は conformance_pack.yaml に分離し、templatefile() で読み込む。

resource "aws_config_conformance_pack" "scs_checks" {
  name          = "${var.project_name}-scs-security-checks"
  template_body = templatefile("${path.module}/conformance_pack.yaml", {})

  depends_on = [aws_config_configuration_recorder_status.main]
}
