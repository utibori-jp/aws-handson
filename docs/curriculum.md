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

* s3-object-lock-governance: S3オブジェクトロックのガバナンスモード有効化と、特権による削除回避の検証（検証後のdestroyを前提）。
* kms-cmk-encryption: KMSのCMKを用いたS3暗号化と、キーポリシーによる厳格なアクセス制御。キー削除スケジュールの自動化を含む。

## 04_Security_Logging_and_Monitoring (セキュリティログとモニタリング)

* vpc-flowlogs-athena: VPCフローログをS3に出力し、Athenaで拒否トラフィックをSQL分析。
* guardduty-threat-detection: GuardDutyを有効化し、サンプル脅威リストを利用して検知を発火、EventBridge経由でSNS通知。カスタム脅威インテルリストとIPセットによる検知精度向上も含む。
* cloudtrail-eventbridge-realtime: CloudTrailの危険なAPI操作（KMSキー削除予約、SG全開放等）をEventBridgeで即時検知し、SNSアラートを通知。
* cloudwatch-metric-alarm: CIS AWS Foundations Benchmarkに準拠したCloudWatchメトリクスフィルタとアラームの実装。ルートユーザー操作・IAMポリシー変更・SG変更等の重要イベントを監視。
* config-conformance-pack: AWS Config Conformance Packによるコンプライアンス評価。CISベンチマーク準拠のマネージドルールセットを適用し、アカウント全体の設定逸脱を継続的に検出。
* security-hub-aggregation: AWS Security HubによるASFF（Amazon Security Finding Format）での検知結果一元集約。GuardDuty・Macie・Config等の検知をクロスサービスで統合管理。

## 05_Threat_Detection_and_Incident_Response (脅威検出とインシデント対応)

* macie-sensitive-data: Amazon Macieを用いたダミー機密データの検出。
* eventbridge-lambda-remediation: 検知した危険なAPI操作（KMS削除予約など）に連動し、Lambdaを発火させて自動で差し戻すカスタムインシデント対応の実装。
* config-ssm-remediation: AWS Config Rulesで「パブリック公開されたS3バケット」等の非準拠を検知し、SSM Automation（マネージドドキュメント）を用いて自動修復するパターンの検証。
* guardduty-auto-remediation: GuardDuty検知（不正IAM認証情報の使用・悪意あるIPからのEC2通信等）をEventBridgeで受け取り、Lambdaによる自動修復（IAMキー無効化・SG隔離）を実装。
* secrets-manager-rotation: Secrets Managerによる認証情報の自動ローテーション。4フェーズ（createSecret / setSecret / testSecret / finishSecret）のLambdaローテーション関数を実装し、RDS等の認証情報ライフサイクルを自動管理。

## 06_Zero_Trust_Architecture (ゼロトラストアーキテクチャ)

* apigw-iam-auth: API GatewayのIAM認証（AWS Signature V4）を利用し、ネットワーク境界に依存しないマイクロサービスへのリクエスト認可を検証。
* verified-access: AWS Verified Accessを構築し、デバイスの状態やID属性に基づくVPNレスなプライベートアプリへのアクセス制御を検証。