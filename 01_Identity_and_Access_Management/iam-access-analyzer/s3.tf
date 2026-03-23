# =============================================================================
# s3.tf — iam-access-analyzer
# Access Analyzer の検出対象となるテスト用 S3 バケット。
#
# このバケットはデフォルトで「パブリックアクセスブロック有効」で作成する。
# 下記の手順で Access Analyzer の検出動作を体験できる。
#
# 【確認ポイント（terraform apply 後）】
# 1. このバケットは非公開状態で作成される（learner アカウント内）
# 2. パブリックアクセスブロックを CLI で解除する
#    ※ この手順だけでは Access Analyzer は検知しない。ブロックを外しても実際にアクセスを許可するポリシーがないため。
#    aws s3api put-public-access-block --bucket scs-handson-analyzer-test \
#      --public-access-block-configuration \
#        BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false \
#      --profile learner-admin
# 3. バケットポリシーでパブリック読み取りポリシーを付与する
#    ※ この手順だけでは実行できない。パブリックアクセスブロックが有効な状態でパブリックポリシーを put するとエラーになる。
#    aws s3api put-bucket-policy --bucket scs-handson-analyzer-test \
#      --policy '{"Statement":[{"Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::scs-handson-analyzer-test/*"}]}' \
#      --profile learner-admin
# 4. Access Analyzer のフィンディングを確認する（数分待つ）
#    # Analyzer 自体の ARN を取得する
#    aws accessanalyzer list-analyzers --profile learner-readonly
#    # フィンディングを一覧する（上記で取得した arn を指定）
#    aws accessanalyzer list-findings-v2 --analyzer-arn <analyzer-arn> --profile learner-readonly
# 5. terraform destroy でクリーンアップ
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
