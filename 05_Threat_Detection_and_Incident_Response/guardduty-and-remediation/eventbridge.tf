# =============================================================================
# eventbridge.tf — guardduty-and-remediation
# 2 つの検知起点（CloudTrail・GuardDuty）から Lambda へルーティングする 4 本のルール。
#
# 【2 つの検知起点の使い分け（SCS 頻出）】
#
# ■ CloudTrail 起点（設定の危険操作を即時検知）
#   CloudTrail 管理イベントは EventBridge デフォルトバスに自動配信される。
#   ルールで eventName をフィルタリングすることで、危険な API 操作を「起きた瞬間」に検知できる。
#   用途：KMS キー削除予約・SG 全開放など「設定の誤り・意図的な破壊」を防ぐ。
#
# ■ GuardDuty 起点（振る舞いの異常を検知）
#   GuardDuty は機械学習・脅威インテリジェンスで「振る舞いの異常」を検知し、
#   finding を EventBridge に発行する（finding_publishing_frequency に従い最大 15 分遅延）。
#   用途：侵害されたキーの不正利用・C2 通信など「攻撃者の行動パターン」に対応する。
#
# 【ルールを分離する理由（最小権限の実現）】
#   1 つのルールで全イベントを受けると、対応 Lambda に広い権限が必要になる。
#   イベントタイプ別にルールを分け、Lambda もロールも分離することで最小権限を実現する。
# =============================================================================

# ---------------------------------------------------------------------------
# CloudTrail 起点 ①：KMS キー削除予約 → cancel_kms_deletion Lambda
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "kms_key_deletion" {
  name        = "${var.project_name}-remediate-kms-deletion"
  description = "Detect ScheduleKeyDeletion and trigger auto-remediation Lambda"

  event_pattern = jsonencode({
    source      = ["aws.kms"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["ScheduleKeyDeletion"]
      # errorCode が存在しない = 成功した API 呼び出しのみを対象にする。
      # 失敗した試みに対して修復を実行しても意味がない。
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
# CloudTrail 起点 ②：SG 全開放 → revoke_sg_ingress Lambda
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
      # EventBridge でイベントパターンに 0.0.0.0/0 を含む操作だけをフィルタリングする。
      # これにより特定の CIDR 許可（社内 IP 等）は Lambda を起動しない。
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

# ---------------------------------------------------------------------------
# GuardDuty 起点 ③：IAM 侵害系フィンディング → remediate_iam_key Lambda
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "guardduty_iam_finding" {
  name        = "${var.project_name}-guardduty-iam-remediation"
  description = "Trigger IAM key remediation for GuardDuty IAMUser findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      type = [
        # IAM ユーザーの認証情報が不正利用されたと思われる系統のフィンディング。
        # prefix マッチで IAMUser 系をすべてキャッチする。
        { prefix = "UnauthorizedAccess:IAMUser/" },
        { prefix = "Recon:IAMUser/" },
        { prefix = "PenTest:IAMUser/" },
        { prefix = "CredentialAccess:IAMUser/" },
      ]
    }
  })

  tags = {
    Name = "${var.project_name}-guardduty-iam-remediation"
  }
}

resource "aws_cloudwatch_event_target" "guardduty_iam_to_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_iam_finding.name
  target_id = "RemediateIAMKey"
  arn       = aws_lambda_function.remediate_iam_key.arn
}

# ---------------------------------------------------------------------------
# GuardDuty 起点 ④：EC2 侵害系フィンディング → isolate_ec2 Lambda
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "guardduty_ec2_finding" {
  name        = "${var.project_name}-guardduty-ec2-remediation"
  description = "Trigger EC2 isolation for GuardDuty EC2 compromise findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      type = [
        # EC2 インスタンスがマルウェアや C2 通信に関与していると思われる系統のフィンディング。
        { prefix = "Backdoor:EC2/" },
        { prefix = "CryptoCurrency:EC2/" },
        { prefix = "Trojan:EC2/" },
        { prefix = "UnauthorizedAccess:EC2/" },
        { prefix = "Behavior:EC2/" },
      ]
    }
  })

  tags = {
    Name = "${var.project_name}-guardduty-ec2-remediation"
  }
}

resource "aws_cloudwatch_event_target" "guardduty_ec2_to_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_ec2_finding.name
  target_id = "IsolateEC2"
  arn       = aws_lambda_function.isolate_ec2.arn
}
