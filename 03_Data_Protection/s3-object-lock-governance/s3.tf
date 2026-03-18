# =============================================================================
# s3.tf — s3-object-lock-governance
# S3 Object Lock（WORM: Write Once Read Many）を有効化したバケット。
# Governance モードの retention ポリシーを設定し、オブジェクトの不正削除を防止する。
#
# 【Object Lock の仕組み】
# - バケット作成時にのみ有効化できる（後から有効化不可）。
# - バージョニングが自動的に有効になる（Object Lock の前提条件）。
# - オブジェクトごとに retention period（保護期間）が設定される。
#
# 【Governance vs Compliance モード】
# - Governance：s3:BypassGovernanceRetention 権限を持つユーザーが retention を上書き・削除できる
#               → ハンズオン・本番でのオペレーション誤り回復に適している
# - Compliance ：誰も（アカウントルートも）期間内は削除できない
#               → 金融・医療など規制要件が厳しい場合に使用。SCS 頻出。
#
# 【ランサムウェア対策としての有効性】
# Object Lock が有効なバケットでは、ランサムウェアによってオブジェクトを上書き・削除しても
# 旧バージョンが保護されるため、バックアップの完全性を保証できる（SCS 頻出テーマ）。
#
# 【⚠️ terraform destroy の注意点】
# retention 期間内のオブジェクトは force_destroy = true でも削除できない。
# destroy 前に README の手順に従い手動削除すること。
# =============================================================================

# Object Lock を有効化した S3 バケット。
# object_lock_enabled = true はバケット作成時にのみ指定できる属性。
# 作成後に変更しても Terraform は無視し、再作成もしない点に注意。
resource "aws_s3_bucket" "protected" {
  bucket = "${var.project_name}-object-lock"

  # ハンズオン用。retention 期間が切れた後の terraform destroy を容易にするための設定。
  # 本番環境ではログ保全・監査要件の観点から false にすること。
  force_destroy = true

  # Object Lock 有効化はバケット作成時のみ。後から変更不可。
  object_lock_enabled = true

  tags = {
    Name = "${var.project_name}-object-lock"
  }
}

# パブリックアクセスを全面ブロック。
# 保護対象データが誤って公開されることを防ぐ。SCS 頻出テーマ。
resource "aws_s3_bucket_public_access_block" "protected" {
  bucket = aws_s3_bucket.protected.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# バージョニングは Object Lock の前提条件として自動的に Enabled になるが、
# Terraform では明示的に設定しないと drift 検知の対象になるため宣言する。
resource "aws_s3_bucket_versioning" "protected" {
  bucket = aws_s3_bucket.protected.id

  versioning_configuration {
    # Object Lock が有効なバケットはバージョニングを無効化できない。
    status = "Enabled"
  }
}

# サーバーサイド暗号化（SSE-S3）を有効化。
# Object Lock と SSE-KMS を組み合わせると、キーポリシーの設定が別途必要になる。
# 本モジュールでは Object Lock の学習に集中するため SSE-S3（AES256）を使用する。
# SSE-KMS との組み合わせは kms-cmk-encryption モジュールで扱う。
resource "aws_s3_bucket_server_side_encryption_configuration" "protected" {
  bucket = aws_s3_bucket.protected.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Object Lock の retention ポリシー設定。
# デフォルトの保持ルールを Governance モード・1日に設定する。
# バケットにデフォルトルールを設定すると、新規オブジェクトに自動で retention が付与される。
resource "aws_s3_bucket_object_lock_configuration" "protected" {
  bucket = aws_s3_bucket.protected.id

  rule {
    default_retention {
      # Governance モード：s3:BypassGovernanceRetention 権限を持つユーザーが上書き可能。
      # Compliance モードに変更するには "COMPLIANCE" にするが、誰も削除できなくなる点に注意。
      mode = "GOVERNANCE"

      # ハンズオン用として最短の 1 日に設定。
      # 本番環境では規制要件に応じて 90 日・365 日・7 年などに設定する。
      days = 1
    }
  }
}

# ---
# デモ用オブジェクト
# ---

# Object Lock による保護を確認するためのサンプルファイル。
# apply 後にこのオブジェクトを削除しようとすると AccessDenied になることを確認できる。
resource "aws_s3_object" "demo" {
  bucket  = aws_s3_bucket.protected.id
  key     = "demo/protected-file.txt"
  content = "This object is protected by S3 Object Lock (Governance mode)."

  tags = {
    Purpose = "Object-Lock-Demo"
  }
}
