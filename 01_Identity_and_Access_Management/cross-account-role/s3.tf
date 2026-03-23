# =============================================================================
# s3.tf — cross-account-role
# peer アカウントにクロスアカウントアクセスの検証用 S3 バケットを作成する。
# AssumeRole なしでは取得できず、クロスアカウントロールを引き受けた後だけ
# アクセスできることを体感するための検証用リソース。
#
# 【アクセス制御の仕組み】
# バケットはパブリックアクセスブロック有効・バケットポリシーなし（デフォルト）。
# つまり「バケット所有者（peer アカウント）か、peer アカウントで権限を持つプリンシパル」
# だけがアクセス可能。learner-admin は learner アカウントの IAM ユーザー/ロールなので
# そのままでは拒否される。ReadOnlyAccess がアタッチされた cross-account ロールを
# 引き受けることで peer アカウントの「権限を持つプリンシパル」として認識される。
# =============================================================================

# ---
# S3 バケット（peer アカウント）
# ---

# 検証用バケット。名前にアカウント ID を含めてグローバル一意性を確保する。
resource "aws_s3_bucket" "peer_demo" {
  provider = aws.peer

  bucket = "${var.project_name}-peer-demo-${var.peer_account_id}"

  tags = {
    Name = "${var.project_name}-peer-demo-bucket"
  }
}

# パブリックアクセスを全てブロック（デフォルト設定を明示）。
# バケットポリシーや ACL による意図しない公開を防ぐ。
resource "aws_s3_bucket_public_access_block" "peer_demo" {
  provider = aws.peer

  bucket = aws_s3_bucket.peer_demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---
# 検証用オブジェクト
# ---

# AssumeRole 後に取得できることを確認するためのファイル。
resource "aws_s3_object" "secret_txt" {
  provider = aws.peer

  bucket  = aws_s3_bucket.peer_demo.id
  key     = "secret.txt"
  content = "This is a secret message from Peer Account!"
}
