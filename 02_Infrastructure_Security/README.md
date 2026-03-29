# 02 Infrastructure Security

## 概要

インフラレベルのセキュリティコントロールを Terraform で実装し、手を動かして理解する章。
SCS 試験で頻出の「ネットワーク境界防御・エッジ保護・コンテナセキュリティ」をカバーする。

## vpc-endpoint-gateway

**前提**: learner アカウント + peer アカウント（VPC はモジュール内で作成）

VPC Gateway Endpoint はルートテーブルにエントリを追加するだけで、NAT Gateway なしに S3 へアクセスできる仕組み。
エンドポイントポリシーはバケットポリシーとは独立した制御レイヤーとして機能し、**VPC 内からのリクエスト全体**に対して適用される。

このモジュールでは `aws:ResourceAccount` 条件で他アカウントの S3 を明示 Deny することで、
VPC 内部のインスタンスが悪用された場合でもデータを外部アカウントに持ち出せないことを確認する。

## cloudfront-waf-oac

**前提**: learner アカウント（VPC 不要）

OAC（Origin Access Control）は S3 オリジンへの直接アクセスを禁止しつつ、CloudFront からの
SigV4 署名リクエストのみを許可する仕組み。バケットポリシーで `aws:SourceArn` を指定することで、
**同一アカウント内の別ディストリビューション経由のアクセスも遮断**できる（Confused Deputy 対策）。

AWS WAF マネージドルールグループ（CommonRuleSet / KnownBadInputs）によるエッジでのリクエストフィルタリングと、
HSTS・X-Frame-Options 等のセキュリティヘッダーによるブラウザ側防御を組み合わせた多層防御を確認する。

## ecs-fargate-security

**前提**: learner アカウント（VPC はモジュール内で作成）

ECS Fargate では**実行ロール**（ECR イメージプル・CloudWatch Logs 書き込みなどタスク起動に必要な権限）と
**タスクロール**（アプリコードが使う権限）を分離するのが基本。タスクロールは最小権限の原則を適用し、
アプリが本当に必要な操作のみを許可する。

コンテナ特有のセキュリティ設定として以下の 3 点を実装し、ECS Exec でコンテナ内に入って効果を直接確認する。

- `readonlyRootFilesystem`: ルートファイルシステムを読み取り専用にしてマルウェアの書き込みを防止
- `noNewPrivileges`: setuid/setgid による権限昇格をカーネルレベルでブロック
- tmpfs マウント: 読み取り専用環境でも `/tmp` 等への一時書き込みを可能にする

## ローカル環境の前提条件

SSM Session Manager を使う確認手順（vpc-endpoint-gateway の EC2 接続・ecs-fargate-security の ECS Exec）を実行するには、session-manager-plugin が必要。

**macOS**
```bash
brew install --cask session-manager-plugin
```

**Ubuntu**
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o session-manager-plugin.deb
sudo dpkg -i session-manager-plugin.deb
```

**Windows (PowerShell)**
```powershell
Invoke-WebRequest `
  -Uri "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPlugin.exe" `
  -OutFile "$env:TEMP\SessionManagerPlugin.exe"
Start-Process -FilePath "$env:TEMP\SessionManagerPlugin.exe" -ArgumentList "/S" -Wait
```

## 共通の始め方

```bash
cd vpc-endpoint-gateway   # 対象モジュールに移動
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集して learner_account_id 等を設定
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```

`learner_account_id` / `peer_account_id` は 00_Baseline の outputs から取得できる。

```bash
cd ../../00_Baseline
terraform output
```
