# =============================================================================
# kms.tf — secrets-manager-rotation
# シークレット暗号化用 CMK。03章（kms-cmk-encryption）のキーポリシーパターンを
# Secrets Manager 向けに適用する。
#
# 【kms:ViaService 条件の意味】
# Secrets Manager 経由のリクエストにのみ復号を許可する。
# CLI から直接 aws kms decrypt を呼んでも復号できない。
# 「シークレットには Secrets Manager API 経由でのみアクセス可能」を強制する（SCS 頻出）。
# =============================================================================

resource "aws_kms_key" "secrets_cmk" {
  description             = "CMK for Secrets Manager encryption - ${var.project_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${local.partition}:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowKeyAdministration"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.arn
        }
        Action = [
          "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
          "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
          "kms:Delete*", "kms:TagResource", "kms:UntagResource",
          "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSecretsManagerUsage"
        Effect = "Allow"
        Principal = {
          AWS     = [data.aws_caller_identity.current.arn]
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # Secrets Manager 経由のリクエストのみを許可する（03章と同じパターン）。
            # s3 ではなく secretsmanager のエンドポイントを指定する点が異なる。
            "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-secrets-cmk"
  }
}

resource "aws_kms_alias" "secrets_cmk" {
  name          = "alias/${var.project_name}-secrets-cmk"
  target_key_id = aws_kms_key.secrets_cmk.key_id
}
