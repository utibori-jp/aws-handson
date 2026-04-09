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
#
# 【確認ポイント】
# apply 後、ジョブ完了まで数分〜十数分待ってから以下を実行する。
#
# 1. ジョブステータス確認（COMPLETE になるまで繰り返す）:
#   aws macie2 describe-classification-job \
#     --job-id "$(terraform output -raw classification_job_id)" \
#     --profile learner-admin --region ap-northeast-1 \
#     --query '{Status: jobStatus, Statistics: statistics}'
#   # → jobStatus が COMPLETE になるまで待つ
#   # → statistics.approximateNumberOfObjectsToProcess でスキャン対象オブジェクト数を確認
#
# 2. フィンディング一覧（ジョブ完了後）:
#   aws macie2 list-findings \
#     --profile learner-admin --region ap-northeast-1 \
#     --query 'findingIds'
#   # → PII が検出された場合にフィンディング ID が表示される
#
# 3. フィンディング詳細（<FINDING_ID> は手順2で取得）:
#   aws macie2 get-findings \
#     --finding-ids "<FINDING_ID>" \
#     --profile learner-admin --region ap-northeast-1 \
#     --query 'findings[0].{Type:type,Severity:severity.description,S3Object:resourcesAffected.s3Object.key,DataIdentifiers:classificationDetails.result.sensitiveData[*].category}'
#   # → Type: SensitiveData:S3Object/Personal
#   # → S3Object: customer-data/test-customers.csv
#   # → DataIdentifiers に FINANCIAL_INFORMATION が含まれること
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
#
# 【destroy 時の注意】
# ONE_TIME ジョブは完了（COMPLETE）後、AWS API レベルで状態変更が禁止される。
# これはガバナンス上の意図的な設計で、「いつ・どのバケットを・誰がスキャンしたか」という
# 監査証跡を事後に改ざん・削除できないようにするため。SOC2 / PCI DSS 等のコンプライアンス要件に対応。
# GuardDuty の findings が 90 日間削除できないのと同じ思想（セキュリティサービスの記録は操作者が消せない）。
#
# Terraform の destroy は内部的に UpdateClassificationJob でジョブを CANCELLED にしようとするが、
# 完了済みジョブには適用できないため ValidationException で失敗する。
# destroy 前に以下で state から切り離す必要がある:
#   terraform state rm aws_macie2_classification_job.scan
#   terraform destroy
# ジョブ記録が AWS 上に残っても追加課金はなく、Macie 無効化後は実害もない。
#
# スキャンを再実行したい場合は CLI で新しいジョブを作成する（既存ジョブの再実行は不可）:
#   ACCOUNT_ID=$(aws sts get-caller-identity --profile learner-admin --query Account --output text)
#   BUCKET=$(terraform output -raw test_bucket_name)
#   aws macie2 create-classification-job \
#     --job-type ONE_TIME \
#     --name "scs-handson-pii-scan-2" \
#     --s3-job-definition "{\"bucketDefinitions\":[{\"accountId\":\"${ACCOUNT_ID}\",\"buckets\":[\"${BUCKET}\"]}]}" \
#     --profile learner-admin --region ap-northeast-1
#
# 【EventBridge への再発行について】
# Macie には重複抑制の仕様があり、同一オブジェクトから同じ種類の findings が検出された場合、
# 既存 finding の更新扱いとなり EventBridge イベントが発火しない。
# EventBridge → SNS → メール の経路を再度テストしたい場合は、
# test_data/test-customers.csv を編集（行追加など）してから terraform apply し、
# S3 オブジェクトを更新した上で新しいジョブを作成する。
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
