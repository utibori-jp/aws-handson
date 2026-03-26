# =============================================================================
# ssm_endpoints.tf — vpc-endpoint-gateway
# SSM Session Manager 用の Interface Endpoint を作成する。
#
# 【Gateway Endpoint vs Interface Endpoint】
# | 項目             | Gateway Endpoint    | Interface Endpoint         |
# |------------------|---------------------|----------------------------|
# | 対象サービス     | S3 / DynamoDB のみ  | ほぼ全ての AWS サービス     |
# | 実装             | ルートテーブルに追記 | ENI（Elastic Network I/F） |
# | セキュリティ制御 | エンドポイントポリシー | SG + エンドポイントポリシー |
# | 料金             | 無料                | 時間課金 + データ転送料金   |
# | Private DNS      | 不可                | 可（VPC 内の DNS で解決）   |
#
# 【Session Manager に必要な Endpoint】
# - ssm          : SSM コントロールプレーンとの通信（UpdateInstanceInformation 等）
# - ssmmessages  : Session Manager のセッション確立・データ転送
# - ec2messages  : Run Command 用（Session Manager 単体では不要のため省略）
#
# 【エンドポイントポリシーと SG の役割分担】
# Interface Endpoint も Gateway Endpoint と同様にエンドポイントポリシーを持てる。
# SG だけでは「どのアカウントの呼び出しか」は制御できないため、両方を使う。
# - SG              : ネットワーク層。「どの IP / SG からの通信を受け付けるか」
# - エンドポイントポリシー : IAM 層。「誰が（どのアカウントが）呼び出せるか」
#
# 【aws:PrincipalAccount vs aws:ResourceAccount】
# このファイルでは aws:PrincipalAccount（呼び出し元アカウント）で制限する。
# S3 Gateway Endpoint（endpoint.tf）の aws:ResourceAccount（リソース側アカウント）と
# 条件キーの向きが逆な点に注意。用途に応じて使い分けることが SCS の頻出論点。
# =============================================================================

# ---
# エンドポイントポリシー（ssm / ssmmessages 共通）
# ---

# データ持ち出し（Exfiltration）の防止：
# EC2 が乗っ取られ、犯人が「自分のアカウントの鍵（--profile）」を EC2 に持ち込んだとしても、
# このエンドポイントを通って犯人の AWS 環境へ通信することを遮断する。
# 例：aws ssm put-parameter --name "Secret" --value "Data" --profile 犯人のアカウント
data "aws_iam_policy_document" "ssm_endpoint" {
  statement {
    sid    = "AllowOwnAccountPrincipal"
    effect = "Allow"

    # 全ての利用者を対象とするが、下の Condition で「自アカウントの身分」のみに絞る。
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["ssm:*", "ssmmessages:*"]
    resources = ["*"]

    # 呼び出し元（プリンシパル）が自アカウントに属している場合のみ許可する。
    # SSM のリソース ARN はサービスによって形式が統一されておらず、
    # ResourceAccount での制限が難しいため、PrincipalAccount を使う。
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
  }
}

# ---
# SSM Endpoint
# ---

resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type = "Interface"

  # Interface タイプは ENI として特定サブネットに配置される。
  # Gateway タイプと異なり、DNS 名で解決して通信する。
  subnet_ids = [aws_subnet.private.id]

  # EC2 SG からのみ受け付けるよう SG で制御する（Gateway には SG がない）。
  security_group_ids = [aws_security_group.ssm_endpoints.id]

  # true にすることで VPC 内の DNS が "ssm.ap-northeast-1.amazonaws.com" を
  # ENI のプライベート IP に解決する。EC2 側のコード変更不要でエンドポイント経由になる。
  private_dns_enabled = true

  policy = data.aws_iam_policy_document.ssm_endpoint.json

  tags = {
    Name = "${var.project_name}-ssm-endpoint"
  }
}

# ---
# SSM Messages Endpoint
# ---

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type = "Interface"

  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true

  policy = data.aws_iam_policy_document.ssm_endpoint.json

  tags = {
    Name = "${var.project_name}-ssmmessages-endpoint"
  }
}
