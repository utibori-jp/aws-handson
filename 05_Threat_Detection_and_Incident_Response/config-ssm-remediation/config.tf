# =============================================================================
# config.tf — config-ssm-remediation
# AWS Config ルールと SSM Automation による自動修復を定義する。
#
# 【本モジュールで扱うパターン】
# Config Rule で「S3 バケットのパブリックアクセスブロックが無効」を検知し、
# SSM Automation（マネージドドキュメント）を使って自動修復する。
#
# 【Config Remediation の仕組み】
# 1. Config Rule がリソースの設定を継続評価
# 2. NON_COMPLIANT（非準拠）になると自動修復アクションが起動
# 3. SSM Automation ドキュメントが修復操作（PutBucketPublicAccessBlock）を実行
# 4. Config がリソースを再評価して COMPLIANT になれば修復完了
#
# 【マネージドドキュメント】
# AWS-DisablePublicAccessForS3Bucket は AWS が提供する SSM マネージドドキュメント。
# パラメータに S3 バケット名を渡すだけで自動的にパブリックアクセスブロックを有効化する。
# カスタムドキュメントを書かずに済むため、03_Data_Protection の延長として
# 「設定のドリフトを継続的に修復する」パターンを最小実装で検証できる。
# =============================================================================

# ---
# Config Recorder（既に有効な場合はこのリソースは不要）
# ---
# Config が有効でないアカウントのために Recorder を定義する。
# 既に Config Recorder が存在する場合は apply 時に競合エラーになるため、
# import してから使うか、このリソースをコメントアウトすること。
#
# 【注意】
# アカウントで Config が既に有効（他章や手動設定）な場合は下記をコメントアウトする。

resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config_recorder.arn

  recording_group {
    # 全リソースタイプを記録する。
    # 特定のリソースタイプのみ記録する場合は all_supported = false にして
    # resource_types リストを指定する（コスト削減に有効）。
    all_supported                 = true
    include_global_resource_types = true
  }
}

# Config Recorder が S3 にスナップショットを届けるためのデリバリーチャンネル。
resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_logs.id

  depends_on = [aws_config_configuration_recorder.main]
}

# Config Recorder を有効化する（作成と有効化は別リソース）。
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# ---
# Config Rule: S3 パブリックアクセスブロック
# ---

# s3-bucket-level-public-access-prohibited:
# S3 バケットレベルのパブリックアクセスブロックが全て有効でないバケットを NON_COMPLIANT にする。
# マネージドルールなので AWS が定義・メンテナンスする（AWS が内容を更新しても自動追従）。
resource "aws_config_config_rule" "s3_public_access_prohibited" {
  name = "${var.project_name}-s3-public-access-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED"
  }

  # Config Recorder が有効でないとルール作成が失敗する。
  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Name = "${var.project_name}-s3-public-access-prohibited"
  }
}

# ---
# Config Remediation Action（自動修復）
# ---

resource "aws_config_remediation_configuration" "s3_public_access" {
  config_rule_name = aws_config_config_rule.s3_public_access_prohibited.name

  # AWS が提供する SSM マネージドドキュメントを使って自動修復する。
  # AWS-DisablePublicAccessForS3Bucket: S3 バケットの全ブロックを有効化する。
  resource_type  = "AWS::S3::Bucket"
  target_type    = "SSM_DOCUMENT"
  target_id      = "AWS-DisablePublicAccessForS3Bucket"
  target_version = "1"

  # SSM Automation の実行ロール。
  execution_controls {
    ssm_controls {
      # 並行実行数の上限。大量の非準拠リソースが一度に修復されることを防ぐ。
      concurrent_execution_rate_percentage = 25
      # 修復失敗率がこの閾値を超えたら全体を停止する（安全装置）。
      error_percentage = 20
    }
  }

  # NON_COMPLIANT になった際に自動で修復を実行する。
  # false にすると手動承認が必要になる（本番環境では承認フローを挟む場合もある）。
  automatic = true

  # 修復の最大再試行回数。
  maximum_automatic_attempts = 3

  # 再試行の間隔（秒）。
  retry_attempt_seconds = 60

  # SSM Automation ドキュメントに渡すパラメータ。
  # BucketName は Config が対象リソースから自動的に解決する。
  parameter {
    name           = "BucketName"
    resource_value = "RESOURCE_ID"
  }

  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.config_remediation.arn
  }
}
