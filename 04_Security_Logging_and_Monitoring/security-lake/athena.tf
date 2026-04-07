# =============================================================================
# athena.tf — security-lake
# Athena クエリ結果の保存先 S3 バケットと専用ワークグループを定義する。
#
# 【なぜ専用ワークグループが必要か】
# Athena のデフォルトワークグループ（primary）はクエリ結果の出力先が未設定のため、
# Security Lake テーブルへのクエリ実行時に出力先バケットが見つからずエラーになる。
# 専用ワークグループに出力先 S3 バケットを設定することで解消する。
#
# 【確認ポイント】
# Athena コンソール → ワークグループ → ${var.project_name}-security-lake を選択してクエリを実行する。
# または以下の CLI で出力先バケットの設定を確認する：
#   aws athena get-work-group \
#     --work-group scs-handson-security-lake \
#     --profile learner-admin \
#     --region ap-northeast-1 \
#     --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation'
# =============================================================================

resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.project_name}-athena-results-${local.account_id}"

  # ハンズオン用途のため destroy 時にクエリ結果オブジェクトごと削除する。
  # 本番環境では false にしてクエリ結果を保護すること。
  force_destroy = true
}

resource "aws_athena_workgroup" "security_lake" {
  name = "${var.project_name}-security-lake"

  configuration {
    result_configuration {
      # クエリ結果を専用バケットに保存する。primary ワークグループとは独立した管理が可能。
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
    }
  }

  # ハンズオン用途のため destroy 時に未完了クエリも含めて削除する。
  force_destroy = true
}
