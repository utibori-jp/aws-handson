# 00_Baseline — 共通インフラ

学習期間中を通じて常時稼働させておくベースライン環境です。
後続の各章（01〜06）はここで作ったリソースを前提に動きます。

## なぜこのリソース構成なのか

### vpc-base（`vpc.tf`）

VPC・サブネット・インターネットゲートウェイを構築します。

- パブリック/プライベートの2層構成にしているのは、後続章でEC2やECSをプライベートに置きつつ、CloudFrontやALBをパブリック側に置く構成を想定しているためです。
- NAT Gatewayは意図的に外しています。常時稼働させると月数千円の固定費が発生するため、ベースラインには含めません。NAT Gatewayが必要なハンズオンは、その章で一時的に追加してください。
- プライベートサブネットへのアクセスは、06章の SSM Session Manager（VPCエンドポイント経由）で代替します。

### cloudtrail-base（`cloudtrail.tf`）

マルチリージョン対応のCloudTrail証跡を有効化し、S3バケットへログを集約します。

- マルチリージョン証跡にしているのは、東京リージョン外での操作（グローバルサービスのAPIコールなど）も漏らさず記録するためです。
- ログファイル整合性検証（`enable_log_file_validation`）を有効化し、ログの改ざん検知を担保しています。これはSCSで頻出の「ログの信頼性確保」に直結する設定です。
- S3バケットポリシーでは `AWS:SourceArn` 条件を使い、自分のCloudTrailからの書き込みのみを許可しています（Confused Deputy問題の対策）。

### iam-base（`iam.tf`）

Terraform実行用の一時権限ロールと、学習用IAMユーザーのベースを作成します。

- Terraform実行ロールはAssumeRole時にMFAを必須とし、普段は管理者権限を持たない設計にしています。「常時Adminのユーザーを作らない」という最小権限の原則を体感するためのものです。
- 学習用ユーザーはReadOnlyAccessをベースとし、各章で必要なポリシーを追加付与していくことを想定しています。01章のIAMハンズオンで、このユーザーへの権限境界設定などを検証します。

## ファイル構成

```
00_Baseline/
├── versions.tf     # Terraform/OpenTofu バージョン制約、プロバイダのピン留め
├── main.tf         # プロバイダ設定、全リソースへの共通タグ付与
├── variables.tf    # 入力変数（リージョン、CIDR、プロファイル名など）
├── vpc.tf          # vpc-base
├── cloudtrail.tf   # cloudtrail-base
├── iam.tf          # iam-base
└── outputs.tf      # 他章から参照するリソースIDの出力
```

## デプロイ手順

```bash
cd 00_Baseline

terraform init
terraform plan
terraform apply
```

## 次のステップ

ベースラインが立ち上がったら [01_Identity_and_Access_Management](../01_Identity_and_Access_Management) へ進んでください。
AssumeRole・権限境界・SCPを使って、このベースライン上に「ガードレール」を構築します。
