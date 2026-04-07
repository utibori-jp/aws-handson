# =============================================================================
# lakeformation.tf — security-lake
# Lake Formation の管理者設定を定義する。
#
# 【なぜ Lake Formation 権限が必要か】
# Security Lake は Glue データカタログ上にテーブルを自動作成し、
# Lake Formation を使ってテーブルへのアクセスを制御する。
# デフォルトでは Lake Formation 管理者（admins）に登録されていない IAM プリンシパルは
# Athena からテーブルにアクセスできず "Access Denied" エラーになる。
# このリソースで SSO ロールを管理者に追加することで Athena クエリが通るようになる。
#
# 【Lake Formation とは】
# S3 データレイク上のデータに対して、データベース・テーブル・列単位の
# きめ細かいアクセス制御を実現する AWS サービス。
# Glue データカタログを基盤とし、IAM ポリシーと組み合わせて使う。
# Security Lake は内部的に Lake Formation を使ってサブスクライバー権限を管理する。
#
# 【⚠️ 注意：admins の上書きとその影響範囲】
# aws_lakeformation_data_lake_settings は「設定の全置き換え」で動作する。
# このリソースを apply すると、既存の admins リストが var.lakeformation_admin_role_arn
# の 1 件だけに上書きされる。
#
# ただし、このハンズオン環境では上書きによる影響はない。理由は以下の通り。
#
# ① Security Lake の SLR（AWSServiceRoleForSecurityLake）は admins リストを使わない
#   Security Lake が内部で Glue テーブルへの読み書きに使うサービスリンクロールは、
#   admins リストではなく「Lake Formation リソースグラント」で権限を持っている。
#   リソースグラントとは「データベース X のテーブル Y を SELECT 可」のような個別付与であり、
#   admins リストとは独立して管理される。admins を上書きしても SLR の権限は消えない。
#
# ② Learner アカウントの admins リストは初期状態で実質空
#   IAM Identity Center（SSO）管理アカウントでは root ユーザーを使わないため、
#   初期状態の admins リストには有効な管理者が登録されていない。
#   上書きしても失う管理者がいない。
#
# ③ 問題になるケース（本番環境での参考）
#   複数の管理者を既に登録済みの環境で apply すると、他の管理者が消える。
#   その場合は admins リストに既存の管理者も列挙すること：
#     admins = [
#       var.lakeformation_admin_role_arn,
#       "arn:aws:iam::xxx:role/other-existing-admin",
#     ]
#
# 【確認ポイント】
# Lake Formation コンソール → 管理 → 管理者とデータベース作成者 で
# SSO ロールが追加されていることを確認する。または：
#   aws lakeformation get-data-lake-settings \
#     --profile learner-admin \
#     --region ap-northeast-1 \
#     --query 'DataLakeSettings.DataLakeAdmins'
# =============================================================================

resource "aws_lakeformation_data_lake_settings" "main" {
  # SSO ロールを Lake Formation 管理者に追加する。
  # admins に指定したプリンシパルは Lake Formation の全テーブルに無制限でアクセスできる。
  # SCS 的観点: 最小権限原則からは外れるが、ハンズオン用途では管理者権限が最も手軽。
  #             本番環境では特定テーブルのみ許可する細粒度制御（GRANT コマンド）を使うこと。
  admins = [var.lakeformation_admin_role_arn]
}
