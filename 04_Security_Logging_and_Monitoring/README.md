# 04 Security Logging and Monitoring

## 概要

検出的コントロール（Detective Controls）を Terraform で実装し、手を動かして理解する章。
00〜03 章で積み上げた「予防的コントロール」から「**検出・監視**」へ移行する。
SCS 試験ドメイン「Security Logging and Monitoring（約 18%）」に対応する。

## cloudwatch-metric-alarm

**前提**: 単一アカウント。Trail・CloudWatch Logs グループを内包する。

CloudTrail モニタリングの2方式を対比して学ぶモジュール。メトリクスフィルター方式では CloudTrail のログを CloudWatch Logs に流し込み、CIS Benchmark が定める6項目（ルート使用・MFA なしログイン・無認可 API コール等）をメトリクス化してアラームを発報する。5 分遅延で集計的に検知するこの方式が CIS の公式推奨アプローチである。EventBridge 直接検知方式では KMS キー削除予約やルートユーザー操作など「1回でも起きたら秒単位で知りたい」重大操作を別ルートで検知する。同一 SNS トピックに両方の通知を集約することで、「なぜ方式を使い分けるのか」という SCS 試験頻出の問いに答えられる設計になっている。

## config-securityhub

**前提**: 単一アカウント。Config の課金に注意（実験後に destroy 推奨）。

AWS Config と Security Hub を組み合わせてコンプライアンス評価とポスチャ可視化を行うモジュール。Config は「リソースの設定状態が正しいか」を継続的に評価する静的評価エンジンであり、Security Hub はその結果を ASFF 形式で集約してセキュリティスコア（0〜100%）として可視化する。両者を一体で体験することで「Config がルールを評価 → Security Hub がスコアを示す」という関係が直感的に理解できる。Conformance Pack には S3 暗号化・IAM MFA・ルートアカウント MFA・ネットワーク系ルールを含め、実際の準拠状況を確認できる。GuardDuty（5章）を有効化すると、このモジュールで構築した Security Hub にフィンディングが自動的に流れ込んでくる。

## vpc-flowlogs-athena

**前提**: 単一アカウント。VPC が必要（変数で既存 VPC を指定するか、モジュールが作成する）。

VPC のネットワークトラフィックをログとして蓄積し、SQL で分析するモジュール。Parquet 形式で S3 に出力し Athena でクエリする構成は、大量ログを低コストで分析する実践的なパターンである。拒否されたトラフィックの一覧・不審 IP からのフロー・大容量転送の上位フローという3種類の名前付きクエリを用意しており、GuardDuty の検知後に「その IP からどんな通信があったか」を深掘りする使い方が想定される。Security Lake モジュールと独立して共存でき、こちらはカスタムフォーマットによる詳細分析、Security Lake 側は OCSF による横断分析という役割分担になる。

## security-lake

**前提**: 単一アカウント。config-securityhub を先に apply しておくと体験価値が高い。

Amazon Security Lake を有効化し、CloudTrail・VPC Flow Logs・Security Hub フィンディングを OCSF（Open Cybersecurity Schema Framework）形式で集約するデータレイクを構成するモジュール。各サービスが独自フォーマットで出力するログを単一の標準スキーマに正規化することで、「CloudTrail の操作ログと VPC Flow Logs を同一クエリで横断分析する」といった高度な調査が可能になる。Security Lake は KMS カスタマーマネージドキーを必須とする点が SCS 試験で問われやすい。サブスクライバーモデル（クエリアクセス型 vs データアクセス型）の違いも頻出トピックである。

## 共通の始め方

```bash
cd cloudwatch-metric-alarm   # 対象モジュールに移動
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集して project_name 等を設定する
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```
