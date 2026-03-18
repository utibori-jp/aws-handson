# =============================================================================
# kms.tf — kms-cmk-encryption
# Customer Managed Key（CMK）を作成し、管理者と利用者を分離したキーポリシーを設定する。
#
# 【CMK vs AWS Managed Key】
# - AWS Managed Key（aws/s3 など）: AWS が自動管理。キーポリシーのカスタマイズ不可。
# - CMK（Customer Managed Key）: 利用者がキーポリシーを完全に制御できる。
#   → 「誰が暗号化/復号できるか」を IAM とは独立したキーポリシーで管理可能（SCS 頻出）。
#
# 【キーポリシーによる職務分離（Separation of Duties）】
# Statement 1: EnableRootAccess
#   → アカウントルートに全権限を付与。
#     キーポリシーを誤って設定した場合のロックアウト防止。
#     「ルートアクセスがないと IAM ポリシーだけではキーにアクセスできない」という重要な原則。
#
# Statement 2: AllowKeyAdministration
#   → Terraform デプロイヤー（terraform-sso）にキー管理権限を付与。
#     kms:Encrypt / kms:Decrypt / kms:GenerateDataKey は含めない。
#     → 「キーを管理できる人は暗号化/復号できない」という職務分離（SCS 頻出）。
#
# Statement 3: AllowKeyUsage
#   → S3 サービスと学習用ユーザーに暗号化/復号権限を付与。
#     kms:ViaService 条件で「S3 経由のみ」に制限する。
#     → キーを直接 CLI から使うことを防ぎ、S3 操作以外での悪用リスクを低減。
#
# 【キー削除スケジュールの仕組み】
# terraform destroy を実行すると KMS は即時削除されず ScheduleKeyDeletion API が呼ばれる。
# deletion_window_in_days（7〜30日）の待機期間後に削除される。
# この間は CancelKeyDeletion で削除をキャンセルできる（誤削除防止）。
# =============================================================================

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

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Statement 1: EnableRootAccess
        # アカウントルートに全権限を付与する。
        # これがないと IAM ポリシーだけでは誰もキーにアクセスできなくなる（ロックアウト）。
        # キーポリシーは IAM ポリシーより優先されるため、この Statement は必須。
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${local.partition}:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Statement 2: AllowKeyAdministration
        # Terraform デプロイヤー（data.aws_caller_identity で取得した実行者）にキー管理権限を付与。
        # 注意：AWS SSO 経由の場合、ARN は assumed-role ARN になる。
        #       キーポリシーでは IAM ロール ARN（assumed-role ARN）も有効。
        Sid    = "AllowKeyAdministration"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.arn
        }
        Action = [
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
          # kms:Encrypt / kms:Decrypt / kms:GenerateDataKey は含めない。
          # → 「キーを管理できる人は暗号化/復号できない」職務分離を実現（SCS 頻出）。
        ]
        Resource = "*"
      },
      {
        # Statement 3: AllowKeyUsage
        # S3 サービスと学習用ユーザーに暗号化/復号権限を付与。
        # kms:ViaService 条件で S3 経由のアクセスのみに制限する。
        Sid    = "AllowKeyUsage"
        Effect = "Allow"
        Principal = {
          AWS = [
            local.learner_user_arn,
            # terraform デプロイヤーも S3 経由での利用を許可（apply/destroy 時の動作確認用）。
            data.aws_caller_identity.current.arn,
          ]
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # S3 サービス経由のリクエストのみを許可する。
            # CLI から直接 kms:Encrypt を呼ぶことを防ぎ、意図しない用途での使用を制限。
            # リージョンを含めた完全なエンドポイント名を指定する（SCS 頻出）。
            "kms:ViaService" = "s3.${var.region}.amazonaws.com"
          }
        }
      }
    ]
  })

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
