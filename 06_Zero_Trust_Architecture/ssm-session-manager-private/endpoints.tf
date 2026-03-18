# =============================================================================
# endpoints.tf
# SSM Session Manager に必要な 3 つの VPC Interface エンドポイント。
#
# NAT Gateway なしでプライベートサブネットの EC2 が AWS サービスと通信できるのは
# これらのエンドポイントがあるから。
#
# 必須エンドポイント:
#   - com.amazonaws.<region>.ssm         : SSM API (セッション制御)
#   - com.amazonaws.<region>.ssmmessages : Session Manager のデータチャネル
#   - com.amazonaws.<region>.ec2messages : SSM Agent ↔ Systems Manager 間のメッセージング
# =============================================================================

locals {
  # エンドポイントをループで作成するためのマップ。
  ssm_endpoints = {
    ssm         = "com.amazonaws.${var.region}.ssm"
    ssmmessages = "com.amazonaws.${var.region}.ssmmessages"
    ec2messages = "com.amazonaws.${var.region}.ec2messages"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = local.ssm_endpoints

  vpc_id              = var.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]

  # private_dns_enabled = true にすることで、EC2 が
  # ssm.ap-northeast-1.amazonaws.com などのパブリック DNS 名を解決したとき
  # VPC 内のエンドポイント IP に誘導される。EC2 側のコード変更が不要になる。
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-endpoint-${each.key}"
  }
}
