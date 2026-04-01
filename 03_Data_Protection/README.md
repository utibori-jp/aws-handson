# 03 Data Protection

## 概要

データ保護のコアコントロールを Terraform で実装し、手を動かして理解する章。
SCS 試験で頻出の「CMK キーポリシー・職務分離・TLS 終端と証明書ライフサイクル管理」をカバーする。

## kms-cmk-encryption

**前提**: learner アカウント + peer アカウント（VPC 不要）

KMS の CMK（Customer Managed Key）は AWS マネージドキーと異なり、「誰が暗号化/復号できるか」をキーポリシーで独立して制御できる。
このモジュールでは Peer アカウントを鍵管理者（セキュリティチーム役）、Learner アカウントを鍵利用者（アプリチーム役）として分離し、
「キーを管理できる人は復号できない」という職務分離（Separation of Duties）を IAM ポリシーではなくキーポリシーで実現する。

誤ったキーポリシーによるロックアウトと `deletion_window_in_days` による誤削除防止の仕組みも合わせて確認することで、
本番環境でのキー管理設計における落とし穴を体感できる。

## acm-tls-encryption

**前提**: learner アカウント（VPC はモジュール内で作成、ドメイン・Route 53 不要）

ACM にはリクエストモード（DNS/メール検証でドメイン所有を証明し AWS が自動更新）と
インポートモード（外部で生成した証明書を持ち込む）の 2 種類がある。
SCS 試験で問われる落とし穴は、**インポート証明書は ACM の有効期限監視・自動更新の対象外**である点。
証明書が失効しても EventBridge アラートは発火せず、CloudWatch メトリクスも記録されない。

このモジュールでは `validity_period_hours = 1` の自己署名証明書を ACM にインポートし、
ALB HTTPS リスナーにアタッチして HTTP→HTTPS リダイレクトと TLS ポリシー選択を実装する。
apply 1 時間後にブラウザで「有効期限切れ」警告が表示されるが ACM からのアラートが来ないことで、
インポート証明書固有の監視設計（EventBridge Scheduler + SNS による残日数チェック）の必要性を直接体感できる。

## 共通の始め方

```bash
cd kms-cmk-encryption   # 対象モジュールに移動
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
