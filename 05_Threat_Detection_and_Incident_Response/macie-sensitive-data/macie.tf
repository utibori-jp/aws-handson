# =============================================================================
# macie.tf — macie-sensitive-data
# Amazon Macie の有効化と分類ジョブの設定。
#
# 【Macie と GuardDuty の役割分担（SCS 最頻出の対比）】
# - GuardDuty: CloudTrail / VPC Flow Logs / DNS ログから「振る舞いの異常」を動的に検知
#              → "何が起きたか"（侵害・攻撃パターン）
# - Macie    : S3 オブジェクトの「内容」を機械学習でスキャンして機密データを静的に検出
#              → "何が入っているか"（PII・認証情報・金融データ）
# 両者は補完関係にある。Macie は「知らずに S3 に置いてしまった機密データ」の発見が主用途。
#
# 【Managed Data Identifier】
# Macie がビルトインで持つ検出パターンのセット。
# CREDIT_CARD_NUMBER / US_SOCIAL_SECURITY_NUMBER / AWS_CREDENTIALS / EMAIL_ADDRESS など
# 100 種類以上のパターンが含まれており、カスタマイズなしで機密データを検出できる。
# =============================================================================

# Macie を有効化する。
# GuardDuty と同様、アカウント単位で有効化され、対象リージョンのリソースをスキャンできる。
resource "aws_macie2_account" "main" {
  # フィンディングの発行頻度。FIFTEEN_MINUTES でハンズオン中に確認できる時間に設定する。
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  # ENABLED にすることで分類ジョブの実行が可能になる。
  status = "ENABLED"
}

# 分類ジョブ（1回限り）。
# ONE_TIME: 1 回だけスキャンして終了。課金が継続しないためハンズオンに適している。
# SCHEDULED: 定期的にスキャン（本番向け。課金継続のためハンズオンでは使わない）。
resource "aws_macie2_classification_job" "scan" {
  job_type = "ONE_TIME"
  name     = "${var.project_name}-pii-scan"

  s3_job_definition {
    bucket_definitions {
      account_id = local.account_id
      # スキャン対象バケットを明示的に指定する。
      # 全バケットスキャン（s3_job_definition を省略）は意図しないスキャンを防ぐため避ける。
      buckets = [aws_s3_bucket.macie_test.bucket]
    }
  }

  # Macie が有効化された後にジョブを作成する。
  depends_on = [
    aws_macie2_account.main,
    aws_s3_object.dummy_pii_csv,
  ]

  tags = {
    Name = "${var.project_name}-pii-scan"
  }
}
