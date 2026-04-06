# =============================================================================
# iam.tf — security-lake
# Security Lake が必要とする IAM ロールを定義する。
#
# 【2種類のロールの使い分け】
# ① AWSServiceRoleForSecurityLake（サービスリンクロール）
#    Security Lake サービス全体の操作（S3・Glue・Lake Formation の管理）に使用する。
#    security_lake.tf の aws_iam_service_linked_role で作成。
#
# ② AmazonSecurityLakeMetaStoreManager（通常 IAM ロール）← このファイルで定義
#    Security Lake のメタストア（Glue カタログ）を管理する Lambda が AssumeRole する。
#    CreateDataLake API の metaStoreManagerRoleArn パラメータに渡す。
#    AmazonSecurityLakeMetastoreManager マネージドポリシーが必要。
# =============================================================================

data "aws_iam_policy_document" "meta_store_manager_trust" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "meta_store_manager" {
  name               = "AmazonSecurityLakeMetaStoreManager"
  assume_role_policy = data.aws_iam_policy_document.meta_store_manager_trust.json

  tags = {
    Name = "AmazonSecurityLakeMetaStoreManager"
  }
}

resource "aws_iam_role_policy_attachment" "meta_store_manager" {
  role       = aws_iam_role.meta_store_manager.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSecurityLakeMetastoreManager"
}
