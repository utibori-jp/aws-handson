# =============================================================================
# iam.tf — config-ssm-remediation
# AWS Config が SSM Automation を呼び出すための実行ロール。
#
# 【SCS 的観点：Config Remediation の権限モデル】
# Config Remediation は「Config サービスが SSM Automation を実行する」構成。
# - Config → SSM Automation 起動に必要: ssm:StartAutomationExecution
# - SSM Automation ドキュメントが S3 バケットを修正するための権限:
#   s3:PutBucketPublicAccessBlock（マネージドドキュメントが使用）
# これらをカスタムロールに集約し、Config Remediation の assumeRole として指定する。
# =============================================================================

# ---
# Config Remediation 実行ロール
# ---

resource "aws_iam_role" "config_remediation" {
  name = "${var.project_name}-config-remediation-role"

  # Config サービスが AssumeRole できるようにする。
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-config-remediation-role"
  }
}

resource "aws_iam_role_policy" "config_remediation" {
  name = "${var.project_name}-config-remediation-policy"
  role = aws_iam_role.config_remediation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # AWS-DisablePublicAccessForS3Bucket マネージドドキュメントが実行する操作。
        # S3 パブリックアクセスブロックの有効化のみ許可する。
        Sid    = "S3PublicAccessBlock"
        Effect = "Allow"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPublicAccessBlock",
        ]
        Resource = "*"
      },
      {
        # SSM Automation の実行に必要な権限。
        Sid    = "SsmAutomation"
        Effect = "Allow"
        Action = [
          "ssm:GetAutomationExecution",
          "ssm:StartAutomationExecution",
        ]
        Resource = "*"
      }
    ]
  })
}
