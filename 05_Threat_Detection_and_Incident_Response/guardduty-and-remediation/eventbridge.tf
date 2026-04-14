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
#
# 【確認ポイント】
# CloudTrail 起点の修復を手動でトリガーして動作を確認する。
#
# 1. KMS キー削除予約 → cancel-kms-deletion Lambda の修復確認
#    # テスト用 KMS キーを作成する
#    KEY_ID=$(aws kms create-key \
#      --description "test-key-for-guardduty-remediation" \
#      --profile learner-admin --region ap-northeast-1 \
#      --query 'KeyMetadata.KeyId' --output text)
#    echo "KeyId: $KEY_ID"
#
#    # 削除予約を実行する（EventBridge → Lambda が即時反応する）
#    aws kms schedule-key-deletion \
#      --key-id "$KEY_ID" \
#      --pending-window-in-days 7 \
#      --profile learner-admin --region ap-northeast-1
#
#    # Lambda ログで自動キャンセルを確認する
#    aws logs tail "/aws/lambda/scs-handson-cancel-kms-deletion" \
#      --follow --profile learner-admin --region ap-northeast-1
#    # → "CancelKeyDeletion succeeded" および "EnableKey succeeded" が記録されることを確認する
#    # → alert_email を設定した場合は SNS 通知メールが届くことを確認する
#
# 2. SG 全開放 → revoke-sg-ingress Lambda の修復確認
#    # デフォルト VPC の ID を取得してテスト用 SG を作成する
#    VPC_ID=$(aws ec2 describe-vpcs \
#      --filters Name=isDefault,Values=true \
#      --profile learner-admin --region ap-northeast-1 \
#      --query 'Vpcs[0].VpcId' --output text)
#    SG_ID=$(aws ec2 create-security-group \
#      --group-name "test-sg-remediation" \
#      --description "test sg for guardduty-and-remediation" \
#      --vpc-id "$VPC_ID" \
#      --profile learner-admin --region ap-northeast-1 \
#      --query 'GroupId' --output text)
#    echo "SgId: $SG_ID"
#
#    # 全開放インバウンドルールを追加する（EventBridge → Lambda が即時反応する）
#    # IPv4 全開放
#    aws ec2 authorize-security-group-ingress \
#      --group-id "$SG_ID" \
#      --protocol tcp --port 22 --cidr 0.0.0.0/0 \
#      --profile learner-admin --region ap-northeast-1
#    # IPv6 全開放（IPv6 が有効な VPC の場合）
#    aws ec2 authorize-security-group-ingress \
#      --group-id "$SG_ID" \
#      --protocol tcp --port 22 --cidr ::/0 \
#      --profile learner-admin --region ap-northeast-1
#
#    # Lambda ログで自動取り消しを確認する
#    aws logs tail "/aws/lambda/scs-handson-revoke-sg-ingress" \
#      --follow --profile learner-admin --region ap-northeast-1
#    # → "Revoked 1 dangerous rule(s)" が記録されることを確認する
#
# 3. 後片付け（terraform destroy の後に実行する）
#    # KMS キー：Lambda がキャンセルして Enabled 状態に戻すため、destroy 後も残り続ける。
#    # 放置すると $1/月/キー のコストが発生する（KMS は即時削除不可・最短 7 日）。
#    aws kms schedule-key-deletion \
#      --key-id "$KEY_ID" \
#      --pending-window-in-days 7 \
#      --profile learner-admin --region ap-northeast-1
#    # 削除予約の確認（KeyState が PendingDeletion になっていることを確認する）
#    aws kms describe-key --key-id "$KEY_ID" \
#      --profile learner-admin --region ap-northeast-1 \
#      --query 'KeyMetadata.{KeyState: KeyState, DeletionDate: DeletionDate}'
#
#    # テスト用 SG：terraform destroy の管理外なので手動で削除する。
#    aws ec2 delete-security-group \
#      --group-id "$SG_ID" \
#      --profile learner-admin --region ap-northeast-1
#    # 削除の確認（InvalidGroup.NotFound エラーが返れば削除済み）
#    aws ec2 describe-security-groups \
#      --group-ids "$SG_ID" \
#      --profile learner-admin --region ap-northeast-1
# =============================================================================

# ---------------------------------------------------------------------------
# CloudTrail 起点 1：KMS キー削除予約 → cancel_kms_deletion Lambda
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
# CloudTrail 起点 2：SG 全開放 → revoke_sg_ingress Lambda
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "sg_ingress_all_open" {
  name        = "${var.project_name}-remediate-sg-ingress"
  description = "Detect AuthorizeSecurityGroupIngress (0.0.0.0/0) and trigger auto-remediation Lambda"

  # EventBridge のイベントパターンは OR 条件で複数の pattern を書けない（AND のみ）。
  # IPv4（0.0.0.0/0）と IPv6（::/0）を 1 つのパターンで同時フィルタできないため、
  # それぞれ別ルールに分けるか、フィルタを外して Lambda 側で判定する方法を取る。
  # ここでは IPv4 と IPv6 のどちらかが存在すれば Lambda を起動するよう
  # cidrIp / cidrIpv6 のフィルタを外し、Lambda 側で全開放ルールを判定する。
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AuthorizeSecurityGroupIngress"]
      errorCode = [{ exists = false }]
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
# GuardDuty 起点 3：IAM 侵害系フィンディング → remediate_iam_key Lambda
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
# GuardDuty 起点 4：EC2 侵害系フィンディング → isolate_ec2 Lambda
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
