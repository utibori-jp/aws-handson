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

### organizations-base（`organizations.tf`）

Organizations メンバーアカウントとして learner アカウントを払い出し、
IAM Identity Center の PermissionSet（Admin / ReadOnly）を割り当てます。

- learner アカウントはハンズオンの動作確認専用です。Terraformの実行には使いません。
- PermissionSet を2種類用意しているのは「リソースを実際に操作して試す（Admin）」と「結果を参照して確認する（ReadOnly）」を使い分けるためです。コンソールはアクセスポータルから、CLIは `--profile` で切り替えます。
- IAM ユーザー（長期アクセスキー）を作らないことで、キー漏洩リスクをゼロにしています。これ自体がSCSの「最小権限・認証情報の保護」のベストプラクティスです。

## ファイル構成

```
00_Baseline/
├── versions.tf       # Terraform/OpenTofu バージョン制約、プロバイダのピン留め
├── main.tf           # プロバイダ設定、全リソースへの共通タグ付与
├── variables.tf      # 入力変数（リージョン、CIDR、メールアドレスなど）
├── vpc.tf            # vpc-base
├── cloudtrail.tf     # cloudtrail-base
├── organizations.tf  # organizations-base（learner アカウント + PermissionSet）
└── outputs.tf        # 他章から参照するリソースIDの出力
```

## デプロイ手順

`learner_account_email` と `sso_username` の入力が必要です。
詳細は [docs/setup.md](../docs/setup.md) を参照してください。

```bash
cd 00_Baseline

terraform init
terraform plan
terraform apply
```

## apply 後の動作確認

### コンソール確認

1. **アクセスポータル** にサインインし、`scs-handson-learner` アカウントが一覧に追加されていることを確認する
2. **IAM Identity Center → AWS アカウント** を開き、learner アカウントに `scs-handson-learner-admin` / `scs-handson-learner-readonly` の2つの許可セットが割り当てられていることを確認する

### CLI 確認

プロファイルの作成方法は [docs/setup.md](../docs/setup.md)（手順6）を参照してください。

#### 権限の違いを確認する

```bash
# Admin でバケットを作成（成功することを確認）
aws s3 mb s3://scs-test-<yourname>-$(date +%Y%m%d) --profile learner-admin

# ReadOnly でバケット一覧を確認（読み取りは成功することを確認）
aws s3 ls --profile learner-readonly

# ReadOnly でバケットを削除（AccessDenied になることを確認）
aws s3 rb s3://scs-test-<yourname>-$(date +%Y%m%d) --profile learner-readonly
# → AccessDenied: s3:DeleteBucket が許可されていないためエラーになる

# Admin でバケットを削除（クリーンアップ）
aws s3 rb s3://scs-test-<yourname>-$(date +%Y%m%d) --profile learner-admin
```

Admin は作成・一覧・削除すべて可能、ReadOnly は一覧のみ可能であることが確認できれば、許可セットが正しく機能しています。

## 次のステップ

ベースラインが立ち上がったら [01_Identity_and_Access_Management](../01_Identity_and_Access_Management) へ進んでください。
AssumeRole・権限境界・SCPを使って、このベースライン上に「ガードレール」を構築します。
