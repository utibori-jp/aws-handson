# =============================================================================
# eventbridge.tf — guardduty-auto-remediation
# GuardDuty フィンディングを侵害タイプ別に分類し、対応する Lambda へルーティングする。
#
# 【ルールを2つに分ける理由】
# IAM 侵害と EC2 侵害は修復の内容・必要な権限・確認手順がまったく異なる。
# 1 つのルールで全フィンディングを Lambda に送ると、
# 「何でも受け取れる Lambda = 広い権限が必要」になってしまう（最小権限原則に反する）。
# ルールを分離することで Lambda も分離でき、各関数に必要な権限だけを付与できる（SCS 頻出の設計）。
# =============================================================================

# ---
# IAM 侵害系フィンディング → remediate_iam_key Lambda
# ---

resource "aws_cloudwatch_event_rule" "iam_remediation" {
  name        = "${var.project_name}-iam-remediation"
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
    Name = "${var.project_name}-iam-remediation"
  }
}

resource "aws_cloudwatch_event_target" "iam_to_lambda" {
  rule      = aws_cloudwatch_event_rule.iam_remediation.name
  target_id = "RemediateIAMKey"
  arn       = aws_lambda_function.remediate_iam_key.arn
}

# ---
# EC2 侵害系フィンディング → isolate_ec2 Lambda
# ---

resource "aws_cloudwatch_event_rule" "ec2_remediation" {
  name        = "${var.project_name}-ec2-remediation"
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
    Name = "${var.project_name}-ec2-remediation"
  }
}

resource "aws_cloudwatch_event_target" "ec2_to_lambda" {
  rule      = aws_cloudwatch_event_rule.ec2_remediation.name
  target_id = "IsolateEC2"
  arn       = aws_lambda_function.isolate_ec2.arn
}
