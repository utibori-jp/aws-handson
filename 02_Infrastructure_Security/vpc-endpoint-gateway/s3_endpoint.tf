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
# データを送信する「データ持ち出し（exfiltration）」攻撃。（SCS頻出）
# → AllowOwnAccountS3 の condition で「自アカウント S3 以外は Allow しない（暗黙の Deny）」ことで防ぐ。
# → DenyOtherAccountS3 は、将来ポリシーが緩んでも上書きできない明示的 Deny としてガードレール的に機能する。
#
# 【確認ポイント】
# 1. VPC コンソールでルートテーブルに「pl-xxxxxxxx（S3 サービスプレフィックス）」の
#    エントリが自動追加されていることを確認する
# 2. エンドポイントポリシーの JSON を確認する
# 3. SSM Session Manager で EC2 に接続し、自アカウントの S3 にアクセスできることを確認
#      # ローカルで実行
#      aws ssm start-session \
#        --profile learner-admin \
#        --target $(terraform output -raw test_instance_id)
#      # EC2 上で実行（バケット名は上記 terraform output endpoint_test_bucket_nam の値に読み替える）:
#      aws s3 ls s3://<endpoint_test_bucket_name>
#      echo "Hello from EC2" > hello.txt
#      aws s3 cp ./hello.txt s3://<endpoint_test_bucket_name>
#      aws s3 ls s3://<endpoint_test_bucket_name>
#      # → hello.txt が表示される。Gateway Endpoint 経由アクセス成功。
# 4. EC2 上で peer アカウントの S3 バケットへのアクセスが Deny されることを確認
#    peer バケットのバケットポリシーは learner EC2 ロールを許可しているため、
#    拒否される原因はエンドポイントポリシー（暗黙の Deny）と特定できる。
#    （検証したければ、AllowOwnAccountS3 の condition ブロックと
#     DenyOtherAccountS3 statement の両方を一時コメントアウトして
#     terraform apply すると peer バケットにアクセスできるようになる）
#      # EC2 上で実行（バケット名は terraform output peer_endpoint_test_bucket_name の値に読み替える）:
#      aws s3 ls s3://<peer_endpoint_test_bucket_name>
#      # → "An error occurred (AccessDenied)" が返ることを確認
# =============================================================================

# ---
# S3 Gateway Endpoint
# ---

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"

  # Gateway タイプ：S3 と DynamoDB のみ対応。料金が発生しない（Interface タイプは有料）。
  # Interface タイプと異なり、ENI は作成されずルートテーブルにエントリが追加される。
  vpc_endpoint_type = "Gateway"

  # エンドポイントのルートを追加するルートテーブルを指定する。
  # プライベートサブネットのルートテーブルに追加することで、
  # NAT Gateway を経由せずに S3 へアクセスできるようになる。
  route_table_ids = [aws_route_table.private.id]

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
  # condition で aws:ResourceAccount を自アカウントに限定することで、
  # 他アカウントの S3 へのリクエストを暗黙の Deny にする（data exfiltration 防止の主体）。
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

  # 他アカウントの S3 バケットへの全操作を明示的に Deny するガードレール。
  # AllowOwnAccountS3 の condition による暗黙の Deny だけでは、
  # 将来 Allow ルールが追加・緩和された場合に上書きされるリスクがある。
  # 明示的 Deny は他の Allow より常に優先されるため、ポリシー変更に対して堅牢。
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
