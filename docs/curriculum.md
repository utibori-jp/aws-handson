# AWS SCS Hands-on Curriculm

## 00_Baseline (共通インフラ)

学習期間中、常時維持するベースライン環境。NAT Gatewayなど時間課金が発生するリソースは排除。

* vpc-base: VPC、サブネット（パブリック/プライベート）、インターネットゲートウェイ。
* cloudtrail-base: 管理アカウントのローカル証跡（マルチリージョン・ログ改ざん検証）とS3バケットへのログ集約。
* organizations: AWS OrganizationsでlearnerとpeerのメンバーアカウントをOUに配置し、IAM Identity Center（SSO）のPermissionSetを割り当て。

## 01_Identity_and_Access_Management (IAMとアクセス管理)

* iam-permissions-boundary: learner-admin PermissionSet（AdministratorAccess）に権限境界を設定し、IAM権限昇格操作（CreatePolicy / AttachRolePolicy / PutRolePolicy 等）をDenyすることで「Admin権限でも権限昇格できない」ことを体感。EC2・S3・CloudWatch Logsのみ許可する境界ポリシーをSSOに直接アタッチ。
* iam-access-analyzer: ACCOUNTスコープのAnalyzerを作成し、S3バケットポリシーで外部アクセスを設定した際にフィンディングが自動検出されることを確認。アーカイブルールによる同一アカウント内アクセスの誤検知抑制も実装。
* cross-account-role: learnerアカウント→peerアカウントへのAssumeRoleを2段階制御（信頼ポリシー＋アイデンティティポリシー）で実装。peerのS3シークレットへのアクセス可否で権限委譲を体感。信頼ポリシーにExternalIdのコメントアウト実装でConfused Deputy問題も学習。
* organizations-scp: ルートユーザーの全操作を禁止するSCP（aws:PrincipalArn条件）と、ap-northeast-1以外のリソース作成を禁止するリージョン制限SCP（NotAction でグローバルサービス除外）を実装。メンバーアカウントへの適用を確認。

## 02_Infrastructure_Security (インフラストラクチャのセキュリティ)

* vpc-endpoint-gateway: 自包VPC内にEC2を配置し、S3ゲートウェイエンドポイントのエンドポイントポリシーで自アカウントS3のみ許可・他アカウントS3を明示Denyすることでデータ持ち出し防止を実装。SSM Session Manager経由でEC2に接続し、peerアカウントのS3バケットへのアクセス拒否を直接確認。
* cloudfront-waf-oac: S3オリジンへの直接アクセスをOAC（SigV4署名 + aws:SourceArn条件）で禁止。CloudFrontにHSTS・X-Frame-Options等のセキュリティヘッダーポリシーと、AWSマネージドルール（CommonRuleSet・KnownBadInputs）を持つWAF Web ACLをアタッチしたエッジ多層防御を実装。
* ecs-fargate-security: 自包VPC内のFargateタスクにreadonlyRootFilesystem・noNewPrivileges・tmpfsマウントを設定し、コンテナへのマルウェア永続化と権限昇格を防止。実行ロール（ECRプル・CloudWatchログ）とタスクロール（アプリ権限）を分離し最小権限を実装。ECS Exec（SSM Session Manager統合）でコンテナ内から権限制限を直接検証。

## 03_Data_Protection (データ保護)

* kms-cmk-encryption: PeerアカウントをCMK管理者・LearnerアカウントをCMK利用者に分離し、「キーを管理できる人は復号できない」というキーポリシーによる職務分離を実装。キー削除スケジュール（deletion_window_in_days）による誤削除防止も確認。
* acm-tls-encryption: tfsプロバイダで自己署名証明書を生成してACMにインポートし、ALBでHTTP→HTTPSリダイレクトとTLSポリシー選択を実装。validity_period_hours=1で証明書を意図的に失効させ、インポート証明書がACMの有効期限監視・自動更新の対象外であることを体感。

## 04_Security_Logging_and_Monitoring (セキュリティログとモニタリング)

* vpc-flowlogs-athena: VPCフローログをParquet形式でS3に出力し、Athenaで拒否トラフィック・不審フロー・大容量転送をSQL分析。カスタムフォーマット（vpc-id/subnet-id/az-id拡張フィールド）採用。
* cloudwatch-metric-alarm: CloudTrailモニタリングの2方式を1モジュールで対比実装。CIS Benchmark準拠のメトリクスフィルタ方式（6項目・5分遅延）とEventBridge直接検知方式（KMSキー削除予約・ルート操作等・秒単位）を同一SNSトピックに集約。
* config-securityhub: AWS Config（Conformance Pack）とSecurity Hub（Organizations統合・委任管理者パターン）を一体実装。管理アカウント→Peer委任管理者→Learnerメンバーの3アカウント構成で、Config評価→SecurityHubスコアリングの関係を体験。
* security-lake: Amazon Security LakeでCloudTrail・VPC Flow Logs・Security HubフィンディングをOCSF（Open Cybersecurity Schema Framework）形式で集約するデータレイク。KMS CMK必須・Lake Formation統合（Athenaクエリアクセス）を実装。サブスクライバーモデル（クエリアクセス型 vs データアクセス型）はコメントアウトしたサンプルコードとして収録。

## 05_Threat_Detection_and_Incident_Response (脅威検出とインシデント対応)

* guardduty-and-remediation: GuardDutyをカスタムThreatIntelSet（既知悪性IPリスト）・IPSet（誤検知除外リスト）で拡張し、検知から自動修復までを一体で構築する。CloudTrail起点ではKMSキー削除予約・SG全開放を「発生した瞬間」にEventBridgeが捕まえてLambdaが即時差し戻す。GuardDuty起点では侵害されたIAM認証情報の使用・EC2の不正通信を受けてキー無効化・SG隔離を実行する。EC2をTerminateではなくIsolate（隔離SGに付け替え）する設計はSCS頻出のフォレンジック証拠保全パターン。
* macie-sensitive-data: GuardDutyが「何が起きたか」（振る舞いの異常）を検知するのに対し、Macieは「何が入っているか」（PII・金融データ）をS3オブジェクトの内容から静的に検出する。クレジットカード番号・SSN等のダミー機密データを含むCSVをS3に配置し、ONE_TIMEジョブで finding生成からEventBridge→SNS通知までのパイプラインを体験する。
