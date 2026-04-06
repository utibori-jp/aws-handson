# =============================================================================
# security_lake.tf — security-lake
# Amazon Security Lake を有効化し、CloudTrail・VPC Flow Logs・Security Hub
# フィンディングを OCSF 形式で集約するデータレイクを構成する。
# ログソース（aws_securitylake_aws_log_source）は「何をレイクに取り込むか」の設定であり、
# 「誰がクエリできるか」のアクセス制御（subscriber.tf）とは独立したライフサイクルを持つ。
# サブスクライバーがいなくてもログの取り込みは行われる。
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
# 【⚠️ 初回 apply の注意事項】
# サービスリンクロール（aws_iam_service_linked_role）が既に存在する場合、
# terraform apply がエラーになる。その際は以下で import してから再実行する。
#   terraform import aws_iam_service_linked_role.security_lake \
#     arn:aws:iam::<learner_account_id>:role/aws-service-role/securitylake.amazonaws.com/AWSServiceRoleForSecurityLake
#
# 【前提条件】terraform apply 前に一度だけ実行する（冪等。実行済みでも安全）
# ─────────────────────────────────────────────────────────────────────────────
# ここで行うのは「Security Lake の有効化」ではなく「Organizations レベルの管理設定」。
# Security Lake 自体の有効化（データレイク作成）は aws_securitylake_data_lake が担う。
#
#   enable-aws-service-access
#     → Organizations が Security Lake サービスと連携することを許可する設定。
#       管理アカウントで Security Lake が有効化されるわけではない。
#
#   register-data-lake-delegated-administrator
#     → Security Lake の管理者権限を learner アカウントに委譲する設定。
#       learner アカウントで Security Lake を有効化できるようになる。
#
# ※ v6.39（2026-04-01リリース）で対応リソースが追加されたが、versions.tf の
#    制約が ~> 6.0 のためバージョン強制を避けて手動手順とする。
#    （対応 PR: hashicorp/terraform-provider-aws#46993）
#    それ以前は aws_organizations_organization の aws_service_access_principals で
#    しか管理できず、組織全体を排他管理する設計のためモジュール単位での利用が困難だった。
# ─────────────────────────────────────────────────────────────────────────────
#   aws organizations enable-aws-service-access \
#     --service-principal securitylake.amazonaws.com \
#     --profile terraform-sso
#
#   aws securitylake register-data-lake-delegated-administrator \
#     --account-id <learner_account_id> \
#     --profile terraform-sso
#
# config-securityhub モジュールを apply 済みの場合、Security Hub Findings ソース
# (SH_FINDINGS) が即座にデータを流し始めるため、apply 前に有効化しておくことを推奨する。
#
# 【確認ポイント】
# ① 有効化されているログソースを確認する
#    aws securitylake list-log-sources \
#      --profile learner-admin \
#      --region ap-northeast-1 \
#      --query 'sources[*].{Account: account, SourceName: sourceName, Status: sourceVersion}' \
#      --output table
#
# ② Security Lake の状態を確認する（INITIALIZED になるまで数分かかる）
#    aws securitylake list-data-lakes \
#      --regions ap-northeast-1 \
#      --profile learner-admin \
#      --query 'dataLakes[*].{Region: region, Status: createStatus, Bucket: s3BucketArn}' \
#      --output table
#
# ③ Athena コンソールで以下のクエリを実行し、OCSF 形式の CloudTrail ログを確認する。
#    データベース名は Security Lake が自動作成する
#    （通常 "amazon_security_lake_glue_db_ap_northeast_1"）。
#
#    SELECT
#      time,
#      cloud.region,
#      actor.user.name,
#      api.operation,
#      api.service.name,
#      src_endpoint.ip
#    FROM amazon_security_lake_glue_db_ap_northeast_1.amazon_security_lake_table_ap_northeast_1_cloud_trail_mgmt_2_0
#    WHERE time_dt > current_timestamp - interval '1' hour
#    ORDER BY time DESC
#    LIMIT 20;
#
# ④ terraform destroy 後、Security Lake が自動作成した S3 バケットを手動削除する
#    （terraform destroy では Security Lake 管理のバケットは自動削除されないため）
#    BUCKET=$(aws securitylake list-data-lakes \
#      --regions ap-northeast-1 \
#      --profile learner-admin \
#      --query 'dataLakes[0].s3BucketArn' --output text | sed 's|arn:aws:s3:::||')
#    aws s3 rb s3://$BUCKET --force --profile learner-admin
# =============================================================================

# ---
# サービスリンクロール
# ---

# Security Lake が Glue・S3・Lake Formation を操作するために必要なサービスリンクロール。
# AWS が自動作成を試みるが、作成完了前に CreateDataLake が走るとエラーになるため明示的に作成する。
# ロールが既に存在する場合は terraform import で取り込む。
#   terraform import aws_iam_service_linked_role.security_lake \
#     arn:aws:iam::<learner_account_id>:role/aws-service-role/securitylake.amazonaws.com/AWSServiceRoleForSecurityLake
resource "aws_iam_service_linked_role" "security_lake" {
  aws_service_name = "securitylake.amazonaws.com"
}

# ---
# Security Lake データレイク
# ---

# Security Lake 本体。S3・Glue・Lake Formation を統合管理する。
# apply 後、指定したリージョンに専用の S3 バケットが自動作成される。
resource "aws_securitylake_data_lake" "main" {
  # CreateDataLake API が metaStoreManagerRoleArn を必須パラメータとして要求するため明示指定する。
  # AWSServiceRoleForSecurityLake（SLR）とは別物。iam.tf で作成した Lambda 実行用ロールを指定する。
  meta_store_manager_role_arn = aws_iam_role.meta_store_manager.arn

  configuration {
    region = var.region

    encryption_configuration {
      # Security Lake 必須の KMS CMK。kms.tfで作成したキーを指定する。
      kms_key_id = aws_kms_key.security_lake.id
    }

    lifecycle_configuration {
      # 本番環境ではトランジションを設定してコストを削減する。
      # Security Lake のログは中期的なフォレンジック調査で参照することが多いため
      # 即時アクセスが必要な期間を過ぎたら Standard-IA へ移行するのが典型的。
      # ハンズオン用途のため無効化している。
      #
      # transition {
      #   days          = 60
      #   storage_class = "STANDARD_IA"
      # }

      # ハンズオン用途のため 7 日で削除する。
      # terraform destroy 後にバケットを消し忘れても 7 日後には空になるため、
      # --force なしの aws s3 rb でも削除できる状態になる。
      # 本番環境では規制要件に合わせて延長すること（PCI DSS: 1年など）。
      expiration {
        days = 7
      }
    }
  }

  depends_on = [
    aws_kms_key.security_lake,
    aws_iam_service_linked_role.security_lake,
    aws_iam_role_policy_attachment.meta_store_manager,
  ]

  tags = {
    Name = "${var.project_name}-security-lake"
  }
}

# ---
# 自動ログソース（AWS Log Sources）
# ---

# CloudTrail 管理イベントを Security Lake に取り込む。
# AWS アカウント内のすべての API コール（コントロールプレーン操作）を OCSF に変換する。
# このモジュールで実際に検証できるログソースはこれのみ。
resource "aws_securitylake_aws_log_source" "cloudtrail" {
  source {
    accounts       = [local.account_id]
    regions        = [var.region]
    source_name    = "CLOUD_TRAIL_MGMT"
    source_version = "2.0"
  }

  depends_on = [aws_securitylake_data_lake.main]
}

# VPC Flow Logs を Security Lake に取り込む設定例。
# このモジュール単体では VPC もトラフィックも存在しないためログは流れない。
resource "aws_securitylake_aws_log_source" "vpc_flow" {
  source {
    accounts       = [local.account_id]
    regions        = [var.region]
    source_name    = "VPC_FLOW"
    source_version = "2.0"
  }

  depends_on = [aws_securitylake_data_lake.main]
}

# Security Hub フィンディングを Security Lake に取り込む設定例。
# このモジュール単体では Security Hub が有効化されていないためログは流れない。
resource "aws_securitylake_aws_log_source" "security_hub" {
  source {
    accounts       = [local.account_id]
    regions        = [var.region]
    source_name    = "SH_FINDINGS"
    source_version = "2.0"
  }

  depends_on = [aws_securitylake_data_lake.main]
}
