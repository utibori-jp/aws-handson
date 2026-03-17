# =============================================================================
# s3.tf — iam-access-analyzer
# Access Analyzer の検出対象となるテスト用 S3 バケット。
#
# このバケットはデフォルトで「パブリックアクセスブロック有効」で作成する。
# 下記の手順で Access Analyzer の検出動作を体験できる。
#
# 【演習手順（terraform apply 後）】
# 1. このバケットは非公開状態で作成される（Access Analyzer に検出されない）
# 2. マネジメントコンソールでパブリックアクセスブロックを手動で無効化する
# 3. バケットポリシーで以下のようなパブリック読み取りポリシーを付与する：
#      {"Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"<arn>/*"}
# 4. Access Analyzer が数分以内に「アクティブ」フィンディングを生成することを確認する
# 5. フィンディングの「アクセス許可」タブで、どのポリシーが原因かを確認する
# 6. terraform destroy でクリーンアップ（force_destroy = true のため削除可能）
# =============================================================================

resource "aws_s3_bucket" "analyzer_test" {
  bucket = "${var.project_name}-analyzer-test"

  # 学習用途のため terraform destroy でバケットを削除できるように設定する。
  # 本番環境ではログ保全の観点から false にすること。
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-analyzer-test"
    Purpose = "AccessAnalyzer-Demo"
  }
}

# パブリックアクセスを全面ブロック（デフォルト安全状態）。
# この設定を手動で変更して Access Analyzer の検出動作を体験する演習に使う。
resource "aws_s3_bucket_public_access_block" "analyzer_test" {
  bucket = aws_s3_bucket.analyzer_test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# サーバーサイド暗号化（SSE-S3）を有効化。
# ハンズオンのベースラインとして常に暗号化を有効にする習慣をつける。
resource "aws_s3_bucket_server_side_encryption_configuration" "analyzer_test" {
  bucket = aws_s3_bucket.analyzer_test.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
