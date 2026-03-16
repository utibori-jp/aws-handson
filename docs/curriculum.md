# AWS SCS Hands-on Curriculm

## 00_Baseline (共通インフラ)

学習期間中、常時維持するベースライン環境。NAT Gatewayなど時間課金が発生するリソースは排除。

* vpc-base: VPC、サブネット（パブリック/プライベート）、インターネットゲートウェイ。
* cloudtrail-base: CloudTrail証跡の有効化とS3バケットへのログ集約。
* iam-base: Terraform実行用の一時権限ロールや、学習用IAMユーザーのベース作成。

## 01_Identity_and_Access_Management (IAMとアクセス管理)

* cross-account-role: 別アカウントへのAssumeRole（信頼ポリシーの設定と権限委譲）の構築と動作確認。
* iam-permissions-boundary: 開発者用IAMロールに対し、特定のサービスしか利用できないように権限境界を設定。
* iam-access-analyzer: CloudTrail履歴に基づく最小権限ポリシーの自動生成と、S3やKMSの「外部公開（パブリック・クロスアカウント）」を検知するZone of Trust Borderの検証。
* organizations-scp: 【追加】AWS Organizationsによるマルチアカウント管理を前提とし、「ルートユーザーの操作制限」や「特定リージョン以外のリソース作成禁止」を適用するガードレールの検証。

## 02_Infrastructure_Security (インフラストラクチャのセキュリティ)

* vpc-endpoint-gateway: S3ゲートウェイエンドポイントを作成し、エンドポイントポリシーによるVPC外へのアクセス制御を検証。
* cloudfront-waf-oac: S3オリジンへの直接アクセスをOACで禁止。CloudFrontに応答ヘッダーポリシーとAWS WAFをアタッチしたエッジ防御を検証。
* ecs-fargate-security: ECS Fargateにおけるタスクロールの最小権限適用や、Read-Only Root Filesystemの有効化など、コンテナ特有のセキュリティ設定の検証。

## 03_Data_Protection (データ保護)

* s3-object-lock-governance: S3オブジェクトロックのガバナンスモード有効化と、特権による削除回避の検証（検証後のdestroyを前提）。
* kms-cmk-encryption: KMSのCMKを用いたS3暗号化と、キーポリシーによる厳格なアクセス制御。キー削除スケジュールの自動化を含む。

## 04_Security_Logging_and_Monitoring (セキュリティログとモニタリング)

* vpc-flowlogs-athena: VPCフローログをS3に出力し、Athenaで拒否トラフィックをSQL分析。
* guardduty-sns-alert: GuardDutyを有効化し、サンプル脅威リストを利用して検知を発火、EventBridge経由でSNS通知。
* cloudtrail-eventbridge-realtime: CloudTrailの危険なAPI操作（KMSキー削除予約、SG全開放等）をEventBridgeで即時検知し、SNSアラートを通知。

## 05_Threat_Detection_and_Incident_Response (脅威検出とインシデント対応)

* macie-sensitive-data: Amazon Macieを用いたダミー機密データの検出。
* eventbridge-lambda-remediation: 検知した危険なAPI操作（KMS削除予約など）に連動し、Lambdaを発火させて自動で差し戻すカスタムインシデント対応の実装。
* config-ssm-remediation: 【修正】AWS Config Rulesで「パブリック公開されたS3バケット」等の非準拠を検知し、SSM Automation（マネージドドキュメント）を用いて自動修復するパターンの検証。

## 06_Zero_Trust_Architecture (ゼロトラストアーキテクチャ)

* ssm-session-manager-private: 【追加】踏み台サーバーを廃止し、SSM Session ManagerとVPCエンドポイントを用いた閉域網からのセキュアなアクセス、およびセッションログのS3出力を検証。
* apigw-iam-auth: 【追加】API GatewayのIAM認証（AWS Signature V4）を利用し、ネットワーク境界に依存しないマイクロサービスへのリクエスト認可を検証。
* verified-access: AWS Verified Accessを構築し、デバイスの状態やID属性に基づくVPNレスなプライベートアプリへのアクセス制御を検証。