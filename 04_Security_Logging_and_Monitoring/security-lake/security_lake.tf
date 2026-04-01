# =============================================================================
# security_lake.tf — security-lake
# Amazon Security Lake を有効化し、CloudTrail・VPC Flow Logs・Security Hub
# フィンディングを OCSF 形式で集約するデータレイクを構成する。
#
# 【Amazon Security Lake とは】
# 複数の AWS サービスのセキュリティログを OCSF（Open Cybersecurity Schema Framework）
# という標準スキーマに正規化して S3 データレイクに集約するサービス。
# SCS-C03 では「マルチアカウント・マルチリージョンのログ集約」文脈で頻出。
#
# 【OCSF（Open Cybersecurity Schema Framework）とは】
# AWS・Splunk・CrowdStrike 等が主導するオープンな標準スキーマ。
# CloudTrail ログも VPC Flow Logs も Security Hub フィンディングも
# 同一の JSON スキーマに正規化されるため、横断的なクエリが可能になる。
# vpc-flowlogs-athena モジュールのカスタム Parquet との違いはここにある。
#
# 【自動収集ソース（AWS Log Sources）】
# 追加設定なしで以下のログを OCSF に変換して取り込める：
# - CLOUD_TRAIL_MGMT: CloudTrail 管理イベント（コントロールプレーン操作）
# - VPC_FLOW:         VPC Flow Logs（ネットワークトラフィック）
# - SH_FINDINGS:      Security Hub フィンディング（ASFF → OCSF 変換）
# - ROUTE53:          Route 53 Resolver クエリログ
#
# 【KMS CMK 必須の理由】
# Security Lake はデータレイクの暗号化に KMS カスタマーマネージドキー（CMK）を必須とする。
# AWS マネージドキーは使えない。CMK を使うことで鍵のローテーション・アクセス制御・
# 鍵の無効化によるデータ保護が可能になる（SCS 頻出）。
#
# 【⚠️ 初回 apply の注意事項】
# Security Lake は初回有効化時に AmazonSecurityLakeMetaStoreManager という
# サービスリンクロールを自動作成する。このロールが存在しないと apply 中に
# AccessDeniedException が発生することがある。
# 再度 terraform apply を実行すると解消する。
#
# 【前提条件】
# config-securityhub モジュールを apply 済みの場合、Security Hub Findings ソース
# (SH_FINDINGS) が即座にデータを流し始めるため、apply 前に有効化しておくことを推奨する。
# =============================================================================

# ---
# KMS カスタマーマネージドキー
# ---

# Security Lake データレイクの暗号化に使用する KMS CMK。
# Security Lake は AWS マネージドキーを受け付けないため、CMK の作成が必須。
resource "aws_kms_key" "security_lake" {
  description             = "CMK for Amazon Security Lake data lake encryption"
  deletion_window_in_days = 7

  # キーローテーションを有効化する。
  # 年1回自動でキーマテリアルが更新される。古い暗号化データは旧キーで復号できる。
  enable_key_rotation = true

  # Security Lake サービスがこのキーを使って暗号化・復号できるようにポリシーを設定する。
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # アカウント管理者に全権限を付与（キーポリシーに root を含めないとキーが管理不能になる）。
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${local.partition}:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Security Lake サービスプリンシパルに暗号化・復号権限を付与する。
        Sid    = "Allow Security Lake Service"
        Effect = "Allow"
        Principal = {
          Service = "securitylake.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-security-lake-key"
  }
}

resource "aws_kms_alias" "security_lake" {
  name          = "alias/${var.project_name}-security-lake"
  target_key_id = aws_kms_key.security_lake.key_id
}

# ---
# Security Lake データレイク
# ---

# Security Lake 本体。S3・Glue・Lake Formation を統合管理する。
# apply 後、指定したリージョンに専用の S3 バケットが自動作成される。
resource "aws_securitylake_data_lake" "main" {
  # Security Lake が Glue・S3・Lake Formation を操作するために使うサービスリンクロール。
  # 初回 apply 時に AWS が自動作成する（AmazonSecurityLakeMetaStoreManager）。
  meta_store_manager_role_arn = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/securitylake.amazonaws.com/AWSServiceRoleForSecurityLake"

  configuration {
    region = var.region

    encryption_configuration {
      # Security Lake 必須の KMS CMK。上で作成したキーを指定する。
      kms_key_id = aws_kms_key.security_lake.arn
    }

    lifecycle_configuration {
      # 60 日後に Standard-IA へ移行してコストを削減する。
      # Security Lake のログは中期的なフォレンジック調査で参照することが多いため
      # 即時アクセスが必要な期間を 60 日と設定している。
      transition {
        days          = 60
        storage_class = "STANDARD_IA"
      }

      # 180 日（約6ヶ月）で削除。
      # 本番環境では規制要件に合わせて延長すること（PCI DSS: 1年など）。
      expiration {
        days = 180
      }
    }
  }

  depends_on = [aws_kms_key.security_lake]

  tags = {
    Name = "${var.project_name}-security-lake"
  }
}

# ---
# 自動ログソース（AWS Log Sources）
# ---

# CloudTrail 管理イベントを Security Lake に取り込む。
# AWS アカウント内のすべての API コール（コントロールプレーン操作）を OCSF に変換する。
resource "aws_securitylake_aws_log_source" "cloudtrail" {
  source {
    accounts       = [local.account_id]
    regions        = [var.region]
    source_name    = "CLOUD_TRAIL_MGMT"
    source_version = "2.0"
  }

  depends_on = [aws_securitylake_data_lake.main]
}

# VPC Flow Logs を Security Lake に取り込む。
# vpc-flowlogs-athena モジュールのカスタム Parquet とは独立した別パイプライン。
# こちらは OCSF に正規化されるため、CloudTrail や Security Hub との横断クエリが可能。
resource "aws_securitylake_aws_log_source" "vpc_flow" {
  source {
    accounts       = [local.account_id]
    regions        = [var.region]
    source_name    = "VPC_FLOW"
    source_version = "2.0"
  }

  depends_on = [aws_securitylake_data_lake.main]
}

# Security Hub フィンディングを Security Lake に取り込む。
# config-securityhub モジュールで有効化した Security Hub のフィンディングが
# OCSF 形式で蓄積される。GuardDuty（5章）有効化後はその検知も含まれる。
resource "aws_securitylake_aws_log_source" "security_hub" {
  source {
    accounts       = [local.account_id]
    regions        = [var.region]
    source_name    = "SH_FINDINGS"
    source_version = "2.0"
  }

  depends_on = [aws_securitylake_data_lake.main]
}
