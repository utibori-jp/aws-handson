# =============================================================================
# eventbridge.tf — eventbridge-lambda-remediation
# CloudTrail の危険な API 操作を EventBridge で検知し、Lambda で自動修復する。
#
# 【イベントパイプラインの構成】
# CloudTrail（管理イベント）
#   → EventBridge デフォルトバス（CloudTrail 管理イベントは自動配信）
#     → EventBridge ルール（危険 API パターンでフィルタリング）
#       → Lambda（差し戻し操作を実行）
#
# 【04章との違い】
# 04/cloudtrail-eventbridge-realtime は「検知して SNS 通知するだけ」。
# 本章は「検知して Lambda で操作を自動差し戻す」能動的インシデントレスポンス。
# 両者を組み合わせることで「検知 + 通知 + 修復」のフルシナリオが完成する。
# =============================================================================

# ---------------------------------------------------------------------------
# 1. KMS キー削除予約 → cancel_kms_deletion Lambda
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "kms_key_deletion" {
  name        = "${var.project_name}-remediate-kms-deletion"
  description = "Detect ScheduleKeyDeletion and trigger auto-remediation Lambda"

  event_pattern = jsonencode({
    source      = ["aws.kms"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["ScheduleKeyDeletion"]
      errorCode = [{ exists = false }]
    }
  })

  tags = {
    Name = "${var.project_name}-remediate-kms-deletion"
  }
}

resource "aws_cloudwatch_event_target" "kms_deletion_to_lambda" {
  rule      = aws_cloudwatch_event_rule.kms_key_deletion.name
  target_id = "KmsDeletionToLambda"
  arn       = aws_lambda_function.cancel_kms_deletion.arn
}

# ---------------------------------------------------------------------------
# 2. SG 全開放 → revoke_sg_ingress Lambda
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "sg_ingress_all_open" {
  name        = "${var.project_name}-remediate-sg-ingress"
  description = "Detect AuthorizeSecurityGroupIngress (0.0.0.0/0) and trigger auto-remediation Lambda"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AuthorizeSecurityGroupIngress"]
      errorCode = [{ exists = false }]
      requestParameters = {
        ipPermissions = {
          items = {
            ipRanges = {
              items = {
                cidrIp = ["0.0.0.0/0"]
              }
            }
          }
        }
      }
    }
  })

  tags = {
    Name = "${var.project_name}-remediate-sg-ingress"
  }
}

resource "aws_cloudwatch_event_target" "sg_ingress_to_lambda" {
  rule      = aws_cloudwatch_event_rule.sg_ingress_all_open.name
  target_id = "SgIngressToLambda"
  arn       = aws_lambda_function.revoke_sg_ingress.arn
}
