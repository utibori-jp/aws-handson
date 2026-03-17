# =============================================================================
# iam.tf — secrets-manager-rotation
# ローテーター Lambda の実行ロール。
# Secrets Manager がローテーション中に使用するバージョン管理 API のみに絞る。
# =============================================================================

resource "aws_iam_role" "rotation_lambda" {
  name = "${var.project_name}-rotation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-rotation-lambda-role"
  }
}

resource "aws_iam_role_policy" "rotation_lambda" {
  name = "${var.project_name}-rotation-lambda-policy"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ローテーション Lambda が Secrets Manager のバージョン管理 API を呼ぶために必要。
        # GetSecretValue: 現在のシークレット値の取得（createSecret フェーズ）
        # PutSecretValue: 新しいシークレット値の保存（createSecret フェーズ）
        # UpdateSecretVersionStage: AWSPENDING → AWSCURRENT への昇格（finishSecret フェーズ）
        # DescribeSecret: バージョン情報・ローテーション設定の取得（全フェーズ）
        Sid    = "SecretsManagerRotation"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:DescribeSecret",
        ]
        Resource = aws_secretsmanager_secret.app_credential.arn
      },
      {
        # シークレットの暗号化/復号に使用する CMK へのアクセス。
        Sid    = "KMSForSecrets"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = aws_kms_key.secrets_cmk.arn
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-rotate-secret:*"
      }
    ]
  })
}
