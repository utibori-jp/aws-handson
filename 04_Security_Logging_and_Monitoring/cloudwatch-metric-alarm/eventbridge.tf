# =============================================================================
# eventbridge.tf — cloudwatch-metric-alarm
# CloudTrail の危険な API 操作を EventBridge ルールでリアルタイム検知し、SNS に転送する。
#
# 【2方式の使い分け（SCS 頻出）】
# このモジュールは CloudTrail モニタリングの2方式を同時に実装している。
#
# ① メトリクスフィルター方式（log_metric_filter.tf + alarms.tf）
#   CloudTrail → CloudWatch Logs → メトリクスフィルター → アラーム → SNS
#   遅延: 約 5 分（CloudWatch の評価周期）
#   適用場面: 「一定期間内に N 回以上発生したら」という集計的な検知
#   CIS Benchmark が明示的にこの方式を要求している
#
# ② EventBridge 直接検知方式（このファイル）
#   CloudTrail 管理イベント → EventBridge デフォルトバス → SNS
#   遅延: 秒単位（ほぼリアルタイム）
#   適用場面: 「1回でも発生したら即座に知りたい」危険操作の検知
#   KMS 削除やルート操作など、発生頻度が低く重大度が高い操作に向く
#
# 【CloudTrail と EventBridge の連携について】
# CloudTrail の管理イベントは追加設定なしで EventBridge のデフォルトバスに自動配信される。
# source = "aws.cloudtrail"、detail-type = "AWS API Call via CloudTrail" で受け取れる。
#
# 【検知対象の API 操作】
# 1. KMS キー削除予約      ← 暗号鍵の削除はデータ喪失につながる重大操作
# 2. SG 全開放            ← 0.0.0.0/0 のインバウンド許可はインフラ露出の典型パターン
# 3. CloudTrail 停止/削除  ← 監査ログを止めることは証跡隠滅の典型手口
# 4. ルートユーザー操作     ← ルートの直接操作は SCS 試験頻出の異常シグナル
# 5. IAM ユーザー作成      ← 不正なバックドアアカウント作成の検知
#
# 【確認ポイント】
# 全ルールが ENABLED 状態になっていることを確認する。
#
# aws events list-rules \
#   --name-prefix "scs-handson-" \
#   --profile learner-admin \
#   --region ap-northeast-1 \
#   --query 'Rules[*].{Name: Name, State: State}' \
#   --output table
#
# KMS 削除予約ルールの発火テスト（CMK を作成して削除予約し、SNS 通知がリアルタイムで届くことを確認する）。
# メトリクスフィルター方式（約 5 分）との遅延差を体感できる。
#
# KEY_ID=$(aws kms create-key \
#   --description "cis-eventbridge-test" \
#   --profile learner-admin \
#   --region ap-northeast-1 \
#   --query 'KeyMetadata.KeyId' --output text)
# aws kms schedule-key-deletion \
#   --key-id "$KEY_ID" \
#   --pending-window-in-days 7 \
#   --profile learner-admin \
#   --region ap-northeast-1
# → SNS に秒単位で通知が届く。
# ※ 削除予約した CMK は Pending deletion 状態のまま最短 7 日間残るが、課金は発生しない。
#   7 日後に AWS が自動削除するため、手動でのクリーンアップは不要。
# =============================================================================

# =============================================================================
# 【EventBridge の detail-type について】
# EventBridge のデフォルトバスには、CloudTrail 以外にも様々な種類のイベントが流れる。
# これらは "detail-type" フィールドによって分類され、ルールでフィルタリングできる。
#
# 1. スケジュールイベント : "Scheduled Event"
#    EventBridge Scheduler や cron 式による定期実行トリガー。
#
# 2. サービスイベント     : "EC2 Instance State-change Notification" など
#    S3 オブジェクト作成や EC2 の状態変化など、リソース自身が自律的に発するイベント。
#
# 3. カスタムイベント     : （任意の文字列）
#    アプリケーションが PutEvents API で投入する独自定義のイベント。
#
# 4. CloudTrail 経由イベント: "AWS API Call via CloudTrail" / "AWS Console Sign In via CloudTrail"
#    ユーザーやサービスによる API コール、コンソール操作の記録。
#
# 本モジュールではセキュリティ監査を目的とするため、4. の CloudTrail 経由イベントを
# 主な監視対象としている。
# =============================================================================

# ---------------------------------------------------------------------------
# 1. KMS キー削除予約（ScheduleKeyDeletion）
# ---------------------------------------------------------------------------
# CMK（カスタマーマネージドキー）の削除を予約した場合に即時アラートを発報する。
# KMS キーが削除されると、そのキーで暗号化されたデータは永続的に復元不能になる。
# 最小待機期間は 7 日だが、予約時点で検知して取り消す機会を確保することが重要。
resource "aws_cloudwatch_event_rule" "kms_key_deletion" {
  name        = "${var.project_name}-kms-key-deletion"
  description = "Detect KMS CMK deletion scheduling (ScheduleKeyDeletion)"

  event_pattern = jsonencode({
    source      = ["aws.kms"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["ScheduleKeyDeletion"]
      # errorCode が存在しないイベント（= 成功した操作）のみを対象にする。
      # 権限エラーで拒否された操作は検知ノイズになるためフィルタする。
      errorCode = [{ exists = false }]
    }
  })

  tags = {
    Name = "${var.project_name}-kms-key-deletion"
  }
}

resource "aws_cloudwatch_event_target" "kms_key_deletion_to_sns" {
  rule      = aws_cloudwatch_event_rule.kms_key_deletion.name
  target_id = "KmsKeyDeletionToSNS"
  arn       = aws_sns_topic.cis_alarms.arn
}

# ---------------------------------------------------------------------------
# 2. セキュリティグループ 全開放（AuthorizeSecurityGroupIngress with 0.0.0.0/0）
# ---------------------------------------------------------------------------
# SG への全 IP 許可（0.0.0.0/0）ルール追加を検知する。
# EventBridge の content filtering（detail フィールドの深い条件）で
# cidrIp を指定してノイズを絞り込む。
# ALB リスナーや公開 API など、0.0.0.0/0 が正当なケースも存在するため、
# このルールは「自動的に問題と判断する」ものではなく「必ず人の目で確認すべき変更を通知する」ものと位置づける。
# 本番環境では、ALB 用 SG の除外やポート番号による絞り込み（例: 443/80 以外はアラート）など
# 運用実態に合わせたチューニングが必要。
resource "aws_cloudwatch_event_rule" "sg_ingress_all_open" {
  name        = "${var.project_name}-sg-ingress-all-open"
  description = "Detect Security Group ingress rule allowing 0.0.0.0/0"

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
                # 0.0.0.0/0 への全開放を検知する。
                # ::/0（IPv6）は別の cidrIpv6 フィールドに入るため別途監視が必要。
                cidrIp = ["0.0.0.0/0"]
              }
            }
          }
        }
      }
    }
  })

  tags = {
    Name = "${var.project_name}-sg-ingress-all-open"
  }
}

resource "aws_cloudwatch_event_target" "sg_ingress_all_open_to_sns" {
  rule      = aws_cloudwatch_event_rule.sg_ingress_all_open.name
  target_id = "SgIngressAllOpenToSNS"
  arn       = aws_sns_topic.cis_alarms.arn
}

# ---------------------------------------------------------------------------
# 3. CloudTrail 停止 / 削除 / 設定変更
# ---------------------------------------------------------------------------
# 証跡の停止・削除・設定変更は監査ログを止める行為であり、インシデント時の
# 証拠隠滅パターンとして知られる（SCS 試験頻出）。
resource "aws_cloudwatch_event_rule" "cloudtrail_changes" {
  name        = "${var.project_name}-cloudtrail-changes"
  description = "Detect CloudTrail trail stop, delete, or configuration changes"

  event_pattern = jsonencode({
    source      = ["aws.cloudtrail"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        "StopLogging",      # 証跡の一時停止
        "DeleteTrail",      # 証跡の削除
        "UpdateTrail",      # 証跡設定の変更（多リージョン無効化、検証無効化など）
        "PutEventSelectors" # 記録対象イベントの変更（管理イベント除外など）
      ]
      errorCode = [{ exists = false }]
    }
  })

  tags = {
    Name = "${var.project_name}-cloudtrail-changes"
  }
}

resource "aws_cloudwatch_event_target" "cloudtrail_changes_to_sns" {
  rule      = aws_cloudwatch_event_rule.cloudtrail_changes.name
  target_id = "CloudTrailChangesToSNS"
  arn       = aws_sns_topic.cis_alarms.arn
}

# ---------------------------------------------------------------------------
# 4. ルートユーザー操作
# ---------------------------------------------------------------------------
# ルートユーザーによるコンソールログインや API 操作を検知する。
# ルートは MFA なしでも全権限を持つため、ルートの直接操作はそれ自体が異常シグナル。
resource "aws_cloudwatch_event_rule" "root_user_activity" {
  name        = "${var.project_name}-root-user-activity"
  description = "Detect any AWS root user activity (console login or API call)"

  event_pattern = jsonencode({
    # コンソールサインインイベントは source が "aws.signin"。
    # API コールは "aws.cloudtrail"。両方をカバーするため $or を使う。
    "$or" = [
      {
        source      = ["aws.signin"]
        detail-type = ["AWS Console Sign In via CloudTrail"]
        detail = {
          userIdentity = {
            type = ["Root"]
          }
        }
      },
      {
        source      = ["aws.cloudtrail"]
        detail-type = ["AWS API Call via CloudTrail"]
        detail = {
          userIdentity = {
            type = ["Root"]
          }
          errorCode = [{ exists = false }]
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-root-user-activity"
  }
}

resource "aws_cloudwatch_event_target" "root_user_activity_to_sns" {
  rule      = aws_cloudwatch_event_rule.root_user_activity.name
  target_id = "RootUserActivityToSNS"
  arn       = aws_sns_topic.cis_alarms.arn
}

# ---------------------------------------------------------------------------
# 5. IAM ユーザー / アクセスキー作成
# ---------------------------------------------------------------------------
# 不正なバックドアアカウント作成やアクセスキー発行を検知する。
# 侵害後に永続的なアクセス手段を確保するために使われるパターン（SCS 頻出）。
# ただし、すべての IAM ユーザー作成を通知すると運用上のアラート疲れ（alert fatigue）が起きやすい。
# 本番環境での改善策:
#   - 操作者で絞り込む: userIdentity（呼び出し元）が既知の CI/CD ロール以外の場合のみ通知
#   - 自動対応を加える: Lambda で DenyAll ポリシーを即時アタッチし、管理者承認まで操作を封じる
# 現状はハンズオン用途のため通知のみ。
resource "aws_cloudwatch_event_rule" "iam_user_key_creation" {
  name        = "${var.project_name}-iam-user-key-creation"
  description = "Detect IAM user creation and access key issuance"

  event_pattern = jsonencode({
    source      = ["aws.iam"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        "CreateUser",        # 新規 IAM ユーザー作成
        "CreateAccessKey",   # アクセスキー発行（既存ユーザー含む）
        "CreateLoginProfile" # コンソールログイン用パスワードの設定
      ]
      errorCode = [{ exists = false }]
    }
  })

  tags = {
    Name = "${var.project_name}-iam-user-key-creation"
  }
}

resource "aws_cloudwatch_event_target" "iam_user_key_creation_to_sns" {
  rule      = aws_cloudwatch_event_rule.iam_user_key_creation.name
  target_id = "IamUserKeyCreationToSNS"
  arn       = aws_sns_topic.cis_alarms.arn
}
