# =============================================================================
# securityhub.tf — config-securityhub
# AWS Security Hub を有効化し、Config・IAM Access Analyzer のフィンディングを集約する。
# Organizations 統合により Peer アカウントを委任管理者として、Learner をメンバーとして構成する。
#
# 【この章での Security Hub の役割】
# 4章（Security Logging and Monitoring）では Security Hub を「コンプライアンス評価・
# ポスチャ可視化」の役割で使う。Config ルールの評価結果や IAM Access Analyzer の
# 外部アクセス検知を ASFF で正規化し、セキュリティスコアとして可視化する。
#
# GuardDuty（脅威検知）との連携は 5章（Threat Detection and Incident Response）で扱う。
# 5章で GuardDuty を有効化すると、このモジュールで構築した Security Hub に
# GuardDuty フィンディングが自動的に流れ込んでくる。
#
# 【Security Hub とは】
# GuardDuty・Config・IAM Access Analyzer などのフィンディングを
# ASFF（Amazon Security Finding Format）という統一フォーマットで正規化・集約するサービス。
# 「セキュリティの一元的な可視性」を提供する（SCS 頻出）。
#
# 【ASFF とは】
# AWS Security Finding Format。各セキュリティサービスが異なるフォーマットで
# 検出結果を出力する問題を解決するための標準 JSON スキーマ。
# フィールド例：ProductArn / GeneratorId / Severity.Label / Remediation.Recommendation
# すべてのフィンディングが同じスキーマで扱えるため、自動化処理（EventBridge → Lambda）が容易になる。
#
# 【Standards（スタンダード）とは】
# Security Hub が評価するセキュリティベストプラクティスのセット。
# - AWS Foundational Security Best Practices（FSBP）: AWS が提供する独自ベストプラクティス
# - CIS AWS Foundations Benchmark 1.2.0: 業界標準のセキュリティ評価基準
# スタンダードに基づいて「セキュリティスコア（0〜100%）」が算出される（SCS 頻出）。
#
# 【Config / Security Hub の役割対比（SCS 頻出）】
# - Config:        設定評価（リソースの静的状態）→ "どういう設定状態か"
# - Security Hub:  上記の集約・正規化・スコアリング → "全体として安全か"
#
# 【Organizations 統合パターン（SCS 頻出）】
# 企業の本番環境では Security Hub を単一アカウントで運用せず、Organizations と統合する。
# 構成の流れ：
#   1. 管理アカウント → Security Hub の委任管理者アカウントを指定
#   2. 委任管理者（このモジュールでは Peer）→ 組織設定でメンバーを自動有効化
#   3. メンバー（Learner）→ フィンディングが委任管理者の画面に集約される
#
# 【なぜ管理アカウントが委任を設定するのか】
# 組織全体に影響するサービス設定の変更は、AWS の設計上、管理アカウントにしか実行できない。
# 管理アカウントは「支払い・Organizations 管理」に特化すべきアカウントで、
# SCP 適用やアカウント作成などの特権を持つため、侵害時の影響が組織全体に及ぶ。
# そのため管理アカウントへのアクセスは最小化するのが原則（最小権限）。
# 委任により、セキュリティチームは管理アカウントにログインせず
# 委任管理者アカウント（Peer）から全組織のフィンディングを管理できる。
# 「Payer とセキュリティ管理アカウントの分離」は手段であり、
# 目的は「管理アカウントへの日常的なアクセスをなくすこと」（SCS 頻出）。
#
# この構成により、セキュリティチームは委任管理者アカウント（Peer）から
# 全メンバーアカウントのフィンディングをひとつの画面で確認できる。
# 個々のメンバーアカウントにログインする必要がなくなる（SCS 頻出の「中央集権的可視性」）。
#
# 【委任管理者と自己管理の違い（SCS 頻出）】
# - 自己管理（単一アカウント）: 各アカウントが自分の SH を個別管理
# - 委任管理者: Organizations 全体のフィンディングを1アカウントで集約
# 試験では「全アカウントの Security Hub フィンディングを一元管理したい」→ 委任管理者パターンが正解
#
# 【⚠️ アカウント単位の制約】
# Security Hub の委任管理者はリージョンごとに1アカウントのみ指定できる。
# 5章のモジュールも Security Hub を利用するため、両モジュールを同時に
# apply した状態にすることはできない。5章を始める前に destroy すること。
#
# 【確認ポイント】
# [管理アカウント] 委任管理者として Peer が登録されているか確認する
# aws securityhub list-organization-admin-accounts \
#   --profile terraform-sso \
#   --region ap-northeast-1
#
# [Peer アカウント] Learner がメンバーとして登録されているか確認する
# aws securityhub list-members \
#   --profile learner-admin \
#   --region ap-northeast-1 \
#   --query 'Members[*].{Account: AccountId, Status: MemberStatus}'
#
# [Learner アカウント] FSBP スタンダードで FAILED になっているコントロールを確認する
# aws securityhub describe-standards-controls \
#   --standards-subscription-arn "$(terraform output -raw fsbp_subscription_arn)" \
#   --profile learner-readonly \
#   --region ap-northeast-1 \
#   --query 'Controls[?ControlStatus==`FAILED`].{Title: Title, Status: ControlStatus, Severity: SeverityRating}' \
#   --output table
#
# [Peer アカウント] Learner のフィンディングが委任管理者から見えるか確認する
# aws securityhub get-findings \
#   --filters '{"SeverityLabel": [{"Value": "HIGH", "Comparison": "EQUALS"}, {"Value": "CRITICAL", "Comparison": "EQUALS"}], "WorkflowStatus": [{"Value": "NEW", "Comparison": "EQUALS"}]}' \
#   --max-results 10 \
#   --profile learner-admin \
#   --region ap-northeast-1 \
#   --query 'Findings[*].{Title: Title, Severity: Severity.Label, AwsAccountId: AwsAccountId, Resource: Resources[0].Id}'
#
# TODO: Security Hub は 2025年12月に大幅アップデートがあった。(https://siliconangle.com/2025/12/02/aws-rolls-security-agent-strengthens-guardduty-security-hub-reinvent-2025/)
# コンソール表示・Central Configuration の挙動・組織設定まわりが変わっている可能性があるため、
# 仕様が安定した時点で以下の手順・コメントを見直すこと。
#
# 【任意】マネコンで Central Configuration の警告を解消する
# terraform apply 後、Peer の Security Hub コンソールに
# 「ポリシーを管理するために必要な権限がありません」という警告が表示される場合がある。
# これは委任管理者が組織全体の設定を管理するための Organizations 委任ポリシーが
# 未作成のために発生する。Terraform 未対応のため手動対応が必要。
# フィンディング確認・スタンダードスコアなどの基本機能は警告があっても動作する。
#
# 手順:
#   1. 管理アカウント（terraform-sso プロファイルのアカウント）のコンソールにログイン
#   2. Security Hub → 設定 → 組織 を開く
#   3. 「委任管理者に権限を自動的に付与」ボタンをクリック
#
# ⚠️ terraform destroy → apply のたびに再実行が必要。
# ただし Organizations 委任ポリシーは Security Hub の delegated admin 指定が
# 削除されると AWS が自動でクリーンアップするため、destroy 時にポリシーが残留する心配はない。
# =============================================================================

# Security Hub を有効化する。
# このリソース1つで現在のリージョンに Security Hub が有効になる。
resource "aws_securityhub_account" "main" {
  # 【コントロールとは】
  # スタンダード内の個別セキュリティチェック項目のこと。
  # 例：「S3.1 - S3 Block Public Access を有効にすること」のような単一の評価ルール。
  # 各コントロールは PASSED / FAILED / NOT_AVAILABLE のいずれかで評価される。
  #
  # auto_enable_controls = true にすると、サブスクリプション済みの全スタンダードに
  # AWS が新しいコントロールを追加した際、自動で有効化される。
  # 実質的には FSBP にのみ効果がある。CIS AWS Foundations Benchmark はバージョンで管理され、
  # 固定バージョン（1.4.0）の内部でコントロールが追加されることはないため。
  auto_enable_controls = true

  # Security Hub が有効化された時点で AWS 側が自動的に FSBP と CIS 1.2.0 の
  # サブスクリプションを作成する機能。true のままにすると、Terraform が後続の
  # aws_securityhub_standards_subscription.fsbp / .cis を作成しようとした時点で
  # AWS 側に既に同じリソースが存在するため "already exists" エラーになる。
  # false にして Terraform が明示的にサブスクリプションを管理するようにする。
  enable_default_standards = false
}

# ---
# スタンダードのサブスクリプション
# ---

# 【スタンダードと製品統合の違い（SCS 頻出）】
# 両者はどちらも「有効化することでフィンディングが Security Hub に集まる」点では共通だが、
# 評価主体とスコアへの影響が異なる。
#
# スタンダード（Standards）:
#   Security Hub 自身が評価エンジンとして動く。Config ルールを使って
#   AWS リソースの設定状態を評価し、フィンディングを生成する。
#   評価結果はセキュリティスコア（0〜100%）に反映される。
#   → Security Hub が能動的に評価する仕組み
#
# 製品統合（Product Subscriptions）:
#   外部サービス（IAM Access Analyzer・GuardDuty など）が自分で検出した結果を
#   ASFF 形式で Security Hub に送り込む。Security Hub は受け取るだけで評価はしない。
#   スコアには影響しない。
#   → 外部サービスが能動的に評価し、Security Hub はパッシブに集約する仕組み

# AWS Foundational Security Best Practices（FSBP）スタンダード。
# AWS が推奨するセキュリティコントロールのセット。
# サブスクリプション後、各コントロールが自動で評価されセキュリティスコアが算出される。
resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:${local.partition}:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]
}

# CIS AWS Foundations Benchmark 1.4.0 スタンダード。
# cloudwatch-metric-alarm モジュールで実装した CIS アラームと同じ基準を
# Security Hub 上でもスコアとして評価できる。
# v1.2.0 は AWS により廃止済み。v1.4.0 が現在有効な最小バージョン。
resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:${local.partition}:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.main]
}

# ---
# 製品統合（Product Subscriptions）
# ---

# IAM Access Analyzer のフィンディングを Security Hub に取り込む。
# 01_IAM 章の iam-access-analyzer モジュールのフィンディングも集約できる。
resource "aws_securityhub_product_subscription" "access_analyzer" {
  product_arn = "arn:${local.partition}:securityhub:${var.region}::product/aws/access-analyzer"

  depends_on = [aws_securityhub_account.main]
}

# =============================================================================
# 以下：Peer アカウント（委任管理者）側のリソース
# =============================================================================

# ---
# Organizations への委任（管理アカウントで実行）
# ---

# ---
# Peer アカウントでの Security Hub 有効化
# ---

# 委任管理者として指定する前に、Peer アカウントで Security Hub を有効化する。
# AWS の EnableOrganizationAdminAccount API は委任時に委任先の SH を自動有効化するため、
# aws_securityhub_account.peer を先に作成しないと 409 conflict が発生する。
resource "aws_securityhub_account" "peer" {
  provider = aws.peer

  auto_enable_controls     = true
  enable_default_standards = false
}

# Peer アカウントを Security Hub の委任管理者に指定する。
# このリソースは管理アカウントで実行する必要があるため provider = aws.management を使用する。
# Peer の SH 有効化（aws_securityhub_account.peer）が完了してから委任を実行する。
# 委任後、Peer は組織全体の Security Hub フィンディングを管理できるようになる。
resource "aws_securityhub_organization_admin_account" "main" {
  provider = aws.management

  admin_account_id = var.peer_account_id

  depends_on = [aws_securityhub_account.peer]
}

# ---
# 組織設定（メンバーの自動有効化）
# ---

# 組織の新規アカウントに Security Hub を自動有効化する設定。
# auto_enable = true にすることで Organizations に参加した新規アカウントが
# 自動的に Security Hub のメンバーとして登録される。
# auto_enable_standards = "NONE" にしてスタンダードは明示的に管理する。
resource "aws_securityhub_organization_configuration" "main" {
  provider = aws.peer

  auto_enable           = true
  auto_enable_standards = "NONE"

  depends_on = [aws_securityhub_account.peer]
}

# ---
# Peer 側スタンダードのサブスクリプション
# ---

# 委任管理者（Peer）でも FSBP スタンダードを有効化する。
# メンバー（Learner）のフィンディングが委任管理者の画面に集約されるため、
# 委任管理者のスコアには全メンバーの状況が反映される。
resource "aws_securityhub_standards_subscription" "peer_fsbp" {
  provider = aws.peer

  standards_arn = "arn:${local.partition}:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.peer]
}

resource "aws_securityhub_standards_subscription" "peer_cis" {
  provider = aws.peer

  standards_arn = "arn:${local.partition}:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.peer]
}

# ---
# Finding Aggregator（委任管理者側でのマルチリージョン集約）
# ---

# Finding Aggregator はすべてのリージョンのフィンディングをホームリージョンに集約する機能。
# 委任管理者（Peer）に配置することで、全メンバー・全リージョンのフィンディングを
# 1か所で確認できる。単一アカウントに置いても効果が薄いため、委任管理者側が正しい配置。
resource "aws_securityhub_finding_aggregator" "main" {
  provider = aws.peer

  # ALL_REGIONS: すべてのリージョンのフィンディングをこのリージョンに集約する。
  linking_mode = "ALL_REGIONS"

  depends_on = [aws_securityhub_account.peer]
}
