# =============================================================================
# endpoint.tf — vpc-endpoint-gateway
# S3 Gateway Endpoint を作成し、エンドポイントポリシーで
# 「他アカウントの S3 バケットへのアクセスを禁止」する。
#
# 【VPC Gateway Endpoint とは】
# VPC 内のリソースが S3 / DynamoDB へアクセスする際、
# インターネットゲートウェイや NAT Gateway を経由せず、
# AWS ネットワーク内部で通信できるようにする仕組み。
# 通信コストの削減とセキュリティ向上（インターネット非経由）が目的。
#
# 【エンドポイントポリシーとは】
# Gateway Endpoint を通過できる API コールを制限するポリシー。
# デフォルトポリシーは「全許可」であり、セキュリティ上問題になりうる。
#
# 【このモジュールで防いでいる脅威】
# 侵害されたインスタンスが、エンドポイント経由で攻撃者の S3 バケットに
# データを送信する「データ持ち出し（exfiltration）」攻撃。
# aws:ResourceAccount 条件で「自アカウントの S3 以外を Deny」することで防ぐ。（SCS頻出）
#
# 【確認ポイント（apply 後）】
# 1. VPC コンソールでルートテーブルに「pl-xxxxxxxx（S3 サービスプレフィックス）」の
#    エントリが自動追加されていることを確認する
# 2. エンドポイントポリシーの JSON を確認する
# 3. EC2 インスタンス（プライベートサブネット）から自アカウントの S3 にアクセスできることを確認
# 4. 他アカウントの S3 バケットへのアクセスが Deny されることを確認
# =============================================================================

# ---
# S3 Gateway Endpoint
# ---

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = var.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"

  # Gateway タイプ：S3 と DynamoDB のみ対応。料金が発生しない（Interface タイプは有料）。
  # Interface タイプと異なり、ENI は作成されずルートテーブルにエントリが追加される。
  vpc_endpoint_type = "Gateway"

  # エンドポイントのルートを追加するルートテーブルを指定する。
  # プライベートサブネットのルートテーブルに追加することで、
  # NAT Gateway を経由せずに S3 へアクセスできるようになる。
  route_table_ids = var.route_table_ids

  policy = data.aws_iam_policy_document.s3_endpoint.json

  tags = {
    Name = "${var.project_name}-s3-gateway-endpoint"
  }
}

# エンドポイントポリシー。
# このポリシーは「エンドポイントを通過できる操作の上限」を定義する。
# VPC 内のリソースのアイデンティティポリシーとの AND で有効権限が決まる（権限境界と同じ考え方）。
data "aws_iam_policy_document" "s3_endpoint" {
  # 自アカウントの S3 バケットへの操作を許可する。
  statement {
    sid    = "AllowOwnAccountS3"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      # 自アカウントの S3 リソースのみ許可する。
      values = [local.account_id]
    }
  }

  # 他アカウントの S3 バケットへの全操作を Deny する。
  # これが「data exfiltration 防止」のキモ。
  # 侵害されたインスタンスが攻撃者のバケットにデータを送ろうとしても、
  # エンドポイントレベルで遮断される。
  statement {
    sid    = "DenyOtherAccountS3"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }
}
