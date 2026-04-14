# =============================================================================
# sns.tf — guardduty-and-remediation
# 修復実行時の通知 SNS トピック。
# Lambda が自動修復を実行した際に管理者へ通知する。
# =============================================================================

resource "aws_sns_topic" "remediation_alerts" {
  name = "${var.project_name}-remediation-alerts"

  tags = {
    Name = "${var.project_name}-remediation-alerts"
  }
}

# SNS へのアクセス制御には2つの方向がある。
#
# ① IAM ロール（Lambda 側に付与）：「この Lambda は SNS に Publish できる」
# ② トピックポリシー（SNS 側に付与）：「この SNS トピックは誰からの Publish を受け入れるか」
#
# 同一アカウント内では①だけでも技術的には動く。
# ただし①のみだと「sns:Publish を持つ IAM エンティティなら誰でも Publish できる」状態になり、
# トピック側で受け入れるプリンシパルを絞れない。
# ②で Lambda ロールの ARN を明示することで、このトピックに Publish できるのは
# この4つの Lambda ロールだけ、という最小権限を実現する。
# クロスアカウントの場合は①②の両方が必須（片方だけでは動かない）。
#
# このモジュールのイベント経路は EventBridge → Lambda → SNS であり、
# SNS を呼び出すのは Lambda 自身（EventBridge ではない）。
# EventBridge が SNS を直接呼ぶ構成であれば Principal に events.amazonaws.com を指定するが、
# ここでは Lambda の IAM ロール ARN を Principal に指定する。
data "aws_iam_policy_document" "sns_remediation_alerts" {
  statement {
    sid    = "AllowLambdaPublish"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.cancel_kms_deletion.arn,
        aws_iam_role.revoke_sg_ingress.arn,
        aws_iam_role.remediate_iam_key.arn,
        aws_iam_role.isolate_ec2.arn,
      ]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.remediation_alerts.arn]
  }
}

resource "aws_sns_topic_policy" "remediation_alerts" {
  arn    = aws_sns_topic.remediation_alerts.arn
  policy = data.aws_iam_policy_document.sns_remediation_alerts.json
}

# メールサブスクリプション（alert_email が指定された場合のみ作成）。
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.remediation_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
