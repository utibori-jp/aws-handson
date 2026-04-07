# =============================================================================
# subscriber.tf — security-lake
# Security Lake のサブスクライバーの概念とサンプルコードを示す。
# このモジュールはシングルアカウント構成のためサブスクライバーは作成しない。
# サブスクライバーは「誰がどのログソースをクエリできるか」のアクセス制御であり、
# ログの取り込み設定（security_lake.tf）とは独立している。
#
# 【サブスクライバーとは】
# Security Lake に蓄積されたデータにアクセスするエンティティ。
# 2種類のアクセス方式がある（SCS 頻出の対比）：
#
# ① クエリアクセス型（LAKEFORMATION）
#   Athena / Lake Formation を通じて S3 上の OCSF データを SQL でクエリする。
#   用途: セキュリティアナリストによる調査・レポート生成
#   仕組み: Lake Formation でテーブルアクセス権を付与 → Athena でクエリ実行
#
# ② データアクセス型（S3_DATA_ACCESS）
#   SQS キューで新着データの通知を受け取り、S3 から直接データを取得する。
#   用途: SIEM・サードパーティセキュリティツールへのリアルタイム連携
#   仕組み: S3 イベント通知 → SQS → サードパーティツールが Pull
#
# 【このモジュールで作らない理由】
# 同一アカウントで Athena クエリするだけなら lakeformation.tf で SSO ロールを
# Lake Formation 管理者に登録する方が手軽で十分。
# サブスクライバーが必要になるのは以下のケース：
#   - クロスアカウントで別アカウントの IAM ロールにクエリを委譲したい
#   - 細粒度のアクセス制御（特定ログソースのみ許可）が必要
#   - SIEM 等のサードパーティツールに S3 直接アクセスさせたい
# =============================================================================

# ---
# サンプルコード: クエリアクセス型サブスクライバー（有効化する場合はコメントを外す）
# ---

# access_type（どうやって）・source（何に）・subscriber_identity（誰が）の3つが揃って
# 「誰が・何のログソースに・どの方式でアクセスできるか」というアクセス制御を定義する。

# resource "aws_securitylake_subscriber" "query" {
#   subscriber_name        = "${var.project_name}-query-subscriber"
#   subscriber_description = "Query access subscriber for Athena-based OCSF analysis"
#
#   # どうやって: Lake Formation 経由のクエリアクセス型（Athena で SQL クエリ）。
#   # "S3_DATA_ACCESS" にすると S3 直接アクセス型（SQS ベースのリアルタイム取得）になる。
#   access_type = "LAKEFORMATION"
#
#   # 何に: アクセスを許可するログソース。
#   source {
#     aws_log_source_resource {
#       source_name    = "CLOUD_TRAIL_MGMT"
#       source_version = "2.0"
#     }
#   }
#
#   source {
#     aws_log_source_resource {
#       source_name    = "VPC_FLOW"
#       source_version = "2.0"
#     }
#   }
#
#   source {
#     aws_log_source_resource {
#       source_name    = "SH_FINDINGS"
#       source_version = "2.0"
#     }
#   }
#
#   # 誰が: アクセスする主体のアカウント ID。
#   # クロスアカウントの場合は principal に対向アカウント ID を指定する。
#   # external_id は接続元の正当性を証明する識別子。
#   # 第三者によるなりすまし（Confused Deputy 問題）を防ぐためクロスアカウント時は必須。
#   subscriber_identity {
#     principal   = local.account_id
#     external_id = "${var.project_name}-security-lake-subscriber"
#   }
#
#   depends_on = [
#     aws_securitylake_aws_log_source.cloudtrail,
#     aws_securitylake_aws_log_source.vpc_flow,
#     aws_securitylake_aws_log_source.security_hub,
#   ]
# }
