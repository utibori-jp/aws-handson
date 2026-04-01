# =============================================================================
# kms.tf — kms-cmk-encryption
# Customer Managed Key（CMK）を作成し、管理者と利用者を分離したキーポリシーを設定する。
# この検証では Peer アカウントが鍵管理アカウント（セキュリティチーム役）を担い、
# Learner アカウントが S3 経由でこのキーを利用する（アプリチーム役）。
#
# 【CMK とは】
# - AWS Managed Key（aws/s3 など）: AWS が自動管理。キーポリシーのカスタマイズ不可。
# - CMK（Customer Managed Key）: 利用者がキーポリシーを完全に制御できる。
#   → 「誰が暗号化/復号できるか」を IAM とは独立したキーポリシーで管理可能（SCS 頻出）。
#
# 【キーポリシーによる職務分離（Separation of Duties）】
# Statement 1: EnableRootAccess
#   → Peer アカウントルートに全権限を付与。
#     キーポリシーを誤って設定した場合のロックアウト防止。
#     「ルートアクセスがないと IAM ポリシーだけではキーにアクセスできない」という重要な原則。
#
# Statement 2: AllowKeyAdministration
#   → Terraform デプロイヤー（Peer アカウントの OrganizationAccountAccessRole）にキー管理権限を付与。
#     kms:Encrypt / kms:Decrypt / kms:GenerateDataKey は含めない。
#     → 「キーを管理できる人は暗号化/復号できない」という職務分離（SCS 頻出）。
#
# Statement 3: AllowKeyUsage
#   → Learner アカウントと S3 サービスに暗号化/復号権限をクロスアカウントで付与。
#     kms:ViaService 条件で「S3 経由のみ」に制限する。
#     → Peer アカウント（鍵管理）と Learner アカウント（鍵利用）が別アカウントになることで
#       職務分離が実現する。
#
# 【キー削除スケジュールの仕組み】
# terraform destroy を実行すると KMS は即時削除されず ScheduleKeyDeletion API が呼ばれる。
# deletion_window_in_days（7〜30日）の待機期間後に削除される。
# この間は CancelKeyDeletion で削除をキャンセルできる（誤削除防止）。
#
# 【確認ポイント】
# 手順 1〜3 はすべて Learner アカウント（learner-admin）から実行する。
#
# 1. SSE-KMS による暗号化成功とメタデータ確認
#    CMK を指定してオブジェクトをアップロードし、ServerSideEncryption が aws:kms であること、
#    および KMSKeyId が Peer アカウントの CMK ARN であることを確認する。
#    # テスト用のファイルをアップロード
#    echo "test content" > /tmp/test.txt
#    aws s3 cp /tmp/test.txt s3://<bucket-name>/test.txt \
#      --profile learner-admin
#    # アップロードしたオブジェクトのメタデータを確認
#    aws s3api head-object \
#      --bucket "<bucket-name>" --key "test.txt" \
#      --profile learner-admin \
#      --query '{SSEAlgorithm: ServerSideEncryption, KMSKeyId: SSEKMSKeyId}'
#    # → ServerSideEncryption: "aws:kms"
#    # → KMSKeyId: "arn:aws:kms:ap-northeast-1:<Peer アカウント ID>:key/..."（Peer の CMK ARN）
#
# 2. バケットポリシーによる SSE-S3 の拒否（防御）
#    --server-side-encryption AES256（SSE-S3）を指定してアップロードを試行し、
#    バケットポリシーの DenyNonCMKEncryption による Explicit Deny を確認する。
#    echo "test content" > /tmp/test.txt
#    aws s3 cp /tmp/test.txt s3://<bucket-name>/test.txt \
#      --sse AES256
#      --profile learner-admin
#    # → AccessDenied: DenyNonCMKEncryption（バケットポリシー）が適用される
#
# 3. キーポリシーによる職務分離の検証（権限管理）
#    Learner アカウントから S3 を経由せずに kms:Encrypt を直接呼び出す。
#    AllowKeyUsage は kms:ViaService 条件付きのため、直接呼び出しでは Allow が適用されず拒否される。
#    → AllowKeyAdministration（管理権限）は kms:Encrypt/Decrypt を意図的に除外している。
#      AllowKeyUsage（利用権限）も S3 経由に限定されている。
#      両者を組み合わせることで、「管理できる者は暗号化/復号できない」「利用できる者も
#      S3 以外の経路では暗号化/復号できない」という二重の職務分離が実現している。
#    aws kms encrypt \
#      --key-id "<CMK ARN>" \
#      --plaintext fileb:///tmp/test.txt \
#      --profile learner-admin
#    # → AccessDenied: kms:ViaService 条件を満たさないため AllowKeyUsage が適用されない
# =============================================================================

data "aws_iam_policy_document" "s3_cmk" {
  statement {
    # Statement 1: EnableRootAccess
    # Peer アカウントルートに全権限を付与する。
    # これがないと IAM ポリシーだけでは誰もキーにアクセスできなくなる（ロックアウト）。
    # キーポリシーは IAM ポリシーより優先されるため、この Statement は必須。
    sid    = "EnableRootAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    # Statement 2: AllowKeyAdministration
    # Terraform デプロイヤー（data.aws_caller_identity で取得した実行者）にキー管理権限を付与。
    # デフォルト provider が Peer アカウントのため、arn = Peer アカウント内の OrganizationAccountAccessRole ARN。
    # 注意：AWS SSO 経由の場合、ARN は assumed-role ARN になる。
    #       キーポリシーでは IAM ロール ARN（assumed-role ARN）も有効。
    # kms:Encrypt / kms:Decrypt / kms:GenerateDataKey は含めない。
    # → 「キーを管理できる人は暗号化/復号できない」職務分離を実現（SCS 頻出）。
    sid    = "AllowKeyAdministration"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.arn]
    }
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:RotateKeyOnDemand",
    ]
    resources = ["*"]
  }

  statement {
    # Statement 3: AllowKeyUsage
    # Learner アカウントと S3 サービスに暗号化/復号権限をクロスアカウントで付与する。
    # Principal に Learner アカウントルートを指定することで、Learner アカウント内の
    # IAM ポリシーに kms:Decrypt 等を持つ任意の ID が鍵を利用できる（クロスアカウント委譲）。
    # kms:ViaService 条件で S3 経由のアクセスのみに制限する。
    # → CLI から直接 kms:Encrypt を呼ぶことを防ぎ、S3 操作以外での悪用リスクを低減。
    sid    = "AllowKeyUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${var.learner_account_id}:root"]
    }
    principals {
      type        = "Service"
      identifiers = ["s3.${var.region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      # リージョンを含めた完全なエンドポイント名を指定する（SCS 頻出）。
      values = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "s3_cmk" {
  description = "CMK for S3 SSE-KMS encryption - ${var.project_name}"

  # 自動ローテーションを有効化。
  # 1 年ごとにキーマテリアルが自動更新される。既存の暗号化データは古いキーマテリアルで
  # 引き続き復号できるため、アプリケーション側の変更は不要。SCS 頻出テーマ。
  enable_key_rotation = true

  # キー削除待機期間（最短 7 日）。ハンズオン用として最短値を使用する。
  # 本番環境では 30 日（デフォルト）が推奨。
  # terraform destroy 後もこの期間内は CancelKeyDeletion でキャンセル可能。
  deletion_window_in_days = 7

  policy = data.aws_iam_policy_document.s3_cmk.json

  tags = {
    Name = "${var.project_name}-s3-cmk"
  }
}

# KMS キーエイリアス。
# エイリアスを使うことでキー ARN の代わりに人間が読めるエイリアス名で参照できる。
# エイリアスは「alias/」プレフィックスが必須。
resource "aws_kms_alias" "s3_cmk" {
  name          = "alias/${var.project_name}-s3-cmk"
  target_key_id = aws_kms_key.s3_cmk.key_id
}
