# =============================================================================
# guardduty.tf — guardduty-and-remediation
# GuardDuty Detector の有効化とカスタム脅威インテリジェンスの登録。
#
# 【GuardDuty はフルマネージド IDS（SCS 最重要ポイント）】
# GuardDuty は「検知ロジックをユーザーが定義する」サービスではない。
# 機械学習・脅威インテリジェンス・ルールセットを AWS が丸ごと管理するフルマネージド検知エンジンで、
# ユーザーが設定できるのは「detector の有効化」「ThreatIntelSet」「IPSet」だけ。
# 「この挙動を異常とみなせ」というカスタム検知ロジックは定義できない。
#
# この特性が試験で問われる場面：
# - 「特定の API 操作を即時検知したい」→ GuardDuty ではなく CloudTrail → EventBridge で自前ルールを書く
# - 「侵害されたキーの不正利用を検知したい」→ GuardDuty の得意領域（振る舞いの異常）
#
# GuardDuty（IDS）と SIEM の違い：
# - SIEM（Security Hub / Splunk 等）：ログを集めてユーザーが検索・ルール定義・相関分析する
# - GuardDuty：データソースを AWS が分析して finding だけ渡す。ログを直接見る必要がない
#
# 【GuardDuty の検知ソース】
# GuardDuty は以下のデータソースを自動的に分析して脅威を検知する：
# - CloudTrail 管理イベント（API 呼び出しの異常）
# - VPC Flow Logs（異常な通信パターン）
# - DNS ログ（C2 ドメインへの問い合わせ）
# これらのログを自前で有効化・保存する必要はなく、GuardDuty が裏側で処理する。
#
# 【finding_publishing_frequency について】
# GuardDuty は新規 finding をまとめて EventBridge に発行する。
# FIFTEEN_MINUTES: 15 分ごと（ハンズオンで素早く確認できる設定）
# ONE_HOUR / SIX_HOURS: 本番向け（コスト最適化）
#
# 【確認ポイント】
# apply 後、以下のコマンドで各リソースを確認する。
# ※ DETECTOR_ID は terraform output -raw guardduty_detector_id で取得する。
#
# 1. ThreatIntelSet・IPSet の登録確認
#    DETECTOR_ID=$(terraform output -raw guardduty_detector_id)
#
#    aws guardduty list-threat-intel-sets \
#      --detector-id "$DETECTOR_ID" \
#      --profile learner-admin --region ap-northeast-1
#
#    aws guardduty list-ip-sets \
#      --detector-id "$DETECTOR_ID" \
#      --profile learner-admin --region ap-northeast-1
#
# 2. GuardDuty IAM サンプル finding を生成する（→ remediate-iam-key Lambda がトリガーされる）
#    aws guardduty create-sample-findings \
#      --detector-id "$DETECTOR_ID" \
#      --finding-types "UnauthorizedAccess:IAMUser/MaliciousIPCaller" \
#      --profile learner-admin --region ap-northeast-1
#    # finding_publishing_frequency = FIFTEEN_MINUTES のため 15 分以内に EventBridge へ発行される。
#
#    # Lambda ログで起動と修復試行を確認する
#    aws logs tail "/aws/lambda/scs-handson-remediate-iam-key" \
#      --follow --profile learner-admin --region ap-northeast-1
#    # サンプルはダミーユーザーのため以下のどちらかのメッセージが出る（SNS 通知は届かない）：
#    # → "No accessKeyDetails found in finding ..." （finding にキー情報なし）
#    # → "User '...' does not exist. This is expected when using GuardDuty sample findings"
#
# 3. GuardDuty EC2 サンプル finding を生成する（→ isolate-ec2 Lambda がトリガーされる）
#    aws guardduty create-sample-findings \
#      --detector-id "$DETECTOR_ID" \
#      --finding-types 'CryptoCurrency:EC2/BitcoinTool.B!DNS' \
#      --profile learner-admin --region ap-northeast-1
#    # ※ finding-types の値に ! が含まれるためシングルクォートで囲む（bash のヒストリ展開を回避）
#
#    # Lambda ログで起動とインスタンス探索を確認する
#    aws logs tail "/aws/lambda/scs-handson-isolate-ec2" \
#      --follow --profile learner-admin --region ap-northeast-1
#    # → "Instance i-xxxx not found. This is expected when using GuardDuty sample findings"
#    #   サンプルのダミーインスタンス ID は存在しないため not_found になる（SNS 通知は届かない）。
# =============================================================================

resource "aws_guardduty_detector" "main" {
  enable = true

  # 15 分ごとにフィンディングを発行する。
  # ハンズオンで create-sample-findings → Lambda 実行 → SNS 通知を素早く確認するための設定。
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "${var.project_name}-guardduty"
  }
}

# ---------------------------------------------------------------------------
# カスタム脅威インテリジェンスリスト（ThreatIntelSet）
# ---------------------------------------------------------------------------
#
# 【なぜ S3 の IP リストを渡すのか】
# GuardDuty は AWS が管理する脅威インテリジェンス（Tor ノード・既知の C2 サーバー等）を
# デフォルトで持っており、これらとの通信を自動的に検知する。
# ThreatIntelSet はそれに「自社独自の悪い IP リスト」を追加する仕組みで、
# GuardDuty が能動的に IP をスキャンするのではなく、
# 「このリストに載っている IP と通信したら finding を出せ」というシグナルを渡す。
#
# 典型的なユースケース：
# - 過去のインシデントで特定した攻撃者 IP
# - ISAC（業界の脅威情報共有組織）から配布された IoC リスト
# - 自社レッドチームの演習用 IP（テスト検知の確認）
#
# 【S3 ファイルを更新しても自動反映されない点に注意】
# Terraform で location を変えず中身だけ更新した場合、GuardDuty は変更を検知しない。
# 本番で IP リストを定期更新する場合は、update-threat-intel-set API を呼ぶ
# Lambda + EventBridge スケジュールを別途用意するのが一般的。
#
# S3 上の IP リストを GuardDuty に登録する。
# このリストの IP と通信があると GuardDuty が finding を生成する。
# ハンズオンではダミー IP のため実際には finding は生成されないが、
# 登録フローとコンソールでの確認を体験できる。
resource "aws_guardduty_threatintelset" "custom" {
  activate    = true
  detector_id = aws_guardduty_detector.main.id
  format      = "TXT"
  location    = "s3://${aws_s3_bucket.threat_intel.bucket}/${aws_s3_object.threat_ips.key}"
  name        = "${var.project_name}-threat-ips"

  depends_on = [aws_s3_bucket_policy.threat_intel]

  tags = {
    Name = "${var.project_name}-threat-ips"
  }
}

# ---------------------------------------------------------------------------
# 信頼 IP セット（IPSet）
# ---------------------------------------------------------------------------

# ThreatIntelSet のホワイトリスト版。
# このリストに登録した IP からの通信は finding を生成しない（除外扱い）。
# 登録しないと、社内ネットワークからの通信や監視ツールのポーリングが
# finding として上がりノイズになる。
# 本番では自社オフィス IP・VPN IP・セキュリティ監視サーバー等を登録する。
resource "aws_guardduty_ipset" "trusted" {
  activate    = true
  detector_id = aws_guardduty_detector.main.id
  format      = "TXT"
  location    = "s3://${aws_s3_bucket.threat_intel.bucket}/${aws_s3_object.trusted_ips.key}"
  name        = "${var.project_name}-trusted-ips"

  depends_on = [aws_s3_bucket_policy.threat_intel]

  tags = {
    Name = "${var.project_name}-trusted-ips"
  }
}
