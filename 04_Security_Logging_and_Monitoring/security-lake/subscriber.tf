# =============================================================================
# subscriber.tf — security-lake
# Security Lake のサブスクライバーを定義する。
#
# 【サブスクライバーとは】
# Security Lake に蓄積されたデータにアクセスするエンティティ。
# 2種類のアクセス方式がある（SCS 頻出の対比）：
#
# ① クエリアクセス型（QUERY_ACCESS）← このモジュールで実装
#   Athena / Lake Formation を通じて S3 上の OCSF データを SQL でクエリする。
#   用途: セキュリティアナリストによる調査・レポート生成
#   仕組み: Lake Formation でテーブルアクセス権を付与 → Athena でクエリ実行
#
# ② データアクセス型（S3_DATA_ACCESS）
#   SQS キューで新着データの通知を受け取り、S3 から直接データを取得する。
#   用途: SIEM・サードパーティセキュリティツールへのリアルタイム連携
#   仕組み: S3 イベント通知 → SQS → サードパーティツールが Pull
#
# 【クロスアカウントシナリオ】
# subscriber_identity の principal に別アカウントの ID を指定することで
# 別アカウントから Security Lake のデータをクエリできる。
# これが「マルチアカウントのセキュリティ運用」の典型構成（SCS 頻出）。
# =============================================================================

# クエリアクセス型サブスクライバー。
# 同一アカウント内から Athena で OCSF データをクエリするための設定。
resource "aws_securitylake_subscriber" "query" {
  subscriber_name        = "${var.project_name}-query-subscriber"
  subscriber_description = "Query access subscriber for Athena-based OCSF analysis"

  # Lake Formation 経由のクエリアクセス型を指定する（Terraform では "LAKEFORMATION" と表記）。
  # "S3" にすると S3 直接アクセス型（SQS ベースのリアルタイム取得）になる。
  access_type = "LAKEFORMATION"

  # サブスクライバーがアクセスできるログソース。
  # ここでは Security Lake に取り込んだすべてのソースにアクセスできるよう設定する。
  source {
    aws_log_source_resource {
      source_name    = "CLOUD_TRAIL_MGMT"
      source_version = "2.0"
    }
  }

  source {
    aws_log_source_resource {
      source_name    = "VPC_FLOW"
      source_version = "2.0"
    }
  }

  source {
    aws_log_source_resource {
      source_name    = "SH_FINDINGS"
      source_version = "2.0"
    }
  }

  # サブスクライバーの ID 情報。
  # principal: データにアクセスするアカウント（ここでは同一アカウント）
  # external_id: クロスアカウントロール引き受け時の Confused Deputy 対策用トークン
  subscriber_identity {
    principal   = local.account_id
    external_id = "${var.project_name}-security-lake-subscriber"
  }

  depends_on = [
    aws_securitylake_aws_log_source.cloudtrail,
    aws_securitylake_aws_log_source.vpc_flow,
    aws_securitylake_aws_log_source.security_hub,
  ]
}
