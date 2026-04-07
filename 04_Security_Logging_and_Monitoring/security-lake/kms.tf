# =============================================================================
# kms.tf — security-lake
# Security Lake データレイクの暗号化に使用する KMS カスタマーマネージドキー（CMK）。
#
# 【KMS CMK 必須の理由】
# Security Lake は AWS マネージドキーを受け付けないため、CMK の作成が必須。
# CMK を使うことで鍵のローテーション・アクセス制御・鍵の無効化によるデータ保護が可能になる。
# =============================================================================

data "aws_iam_policy_document" "security_lake_kms" {
  # アカウント管理者に全権限を付与する。
  # キーポリシーに root を含めないとキーが IAM で管理不能になるため必須。
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Security Lake サービスプリンシパルに暗号化・復号権限を付与する。
  # aws:SourceAccount 条件で自アカウントの Security Lake のみに限定する（Confused Deputy 対策）。
  statement {
    sid    = "Allow Security Lake Service"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["securitylake.amazonaws.com"]
    }

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Security Lake リソース管理用 SLR に暗号化・復号権限を付与する。
  # AWSServiceRoleForSecurityLakeResourceManagement は Security Lake が
  # S3 バケットへのデータ書き込み・読み取り時に使用する SLR。
  # サービスプリンシパルではなくロールとして直接 KMS にアクセスするため、
  # securitylake.amazonaws.com への許可とは別に必要。
  statement {
    sid    = "Allow Security Lake Resource Management SLR"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/resource-management.securitylake.amazonaws.com/AWSServiceRoleForSecurityLakeResourceManagement"]
    }

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "security_lake" {
  description             = "CMK for Amazon Security Lake data lake encryption"
  deletion_window_in_days = 7

  # 年1回自動でキーマテリアルが更新される。古い暗号化データは旧キーで復号できる。
  enable_key_rotation = true

  policy = data.aws_iam_policy_document.security_lake_kms.json

  tags = {
    Name = "${var.project_name}-security-lake-key"
  }
}

resource "aws_kms_alias" "security_lake" {
  name          = "alias/${var.project_name}-security-lake"
  target_key_id = aws_kms_key.security_lake.key_id
}
