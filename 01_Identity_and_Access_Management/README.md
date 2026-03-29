# 01 Identity and Access Management

## 概要

IAM のコアコンセプトを Terraform で実装し、手を動かして理解する章。
SCS 試験で頻出の「最小権限・権限委譲・外部アクセス検出・予防的コントロール」をカバーする。

## iam-permissions-boundary

**前提**: learner アカウント（00_Baseline 必須）

権限境界は「実際の有効権限 = アイデンティティポリシー ∩ 権限境界」という AND 条件で機能する。
Admin 権限を持っていても境界の外側にある操作は暗黙の Deny となるため、
開発者が自分の権限を昇格させる「権限昇格攻撃」を組織的にブロックできる。

このモジュールでは learner-admin PermissionSet（AdministratorAccess）に境界を直接アタッチし、
「Admin 権限を持ちながら IAM 操作は拒否される」状態を実際に確認する。

## iam-access-analyzer

**前提**: learner アカウント（00_Baseline 必須）

IAM Access Analyzer はリソースポリシーを継続的に解析し、信頼ゾーン外からアクセス可能な
リソースを自動検出する。S3・KMS・IAM ロール・Lambda など幅広いリソースタイプが対象で、
意図しない公開設定を「作ったときではなく変えたとき」に検知できる点が重要。

アーカイブルールを使うと既知・意図的な外部アクセスをノイズとして除外でき、
本当に調査が必要なフィンディングだけに集中できる。

## cross-account-role

**前提**: learner アカウント + peer アカウント（00_Baseline 必須）

クロスアカウントアクセスは「peer 側の信頼ポリシー」と「learner 側のアイデンティティポリシー」の
両方が揃って初めて成立する AND 条件。どちらか一方だけでは AssumeRole できない点が SCS 頻出の落とし穴。

このモジュールでは AssumeRole で取得した一時認証情報を使い、learner アカウントのユーザーが
peer アカウントの S3 オブジェクトにアクセスできることを確認する。

## organizations-scp

**前提**: learner アカウント（00_Baseline 必須・管理アカウントで実行）

SCP は IAM ポリシーとは独立した「権限の上限（ガードレール）」として機能し、
アカウント内のすべての IAM エンティティに適用される。IAM では制限できないルートユーザーの操作も
SCP で技術的にエンフォースできる点が SCS 的に重要。

このモジュールではルートユーザー制限とリージョン制限の 2 種類の SCP を実装する。
管理アカウント自体は SCP の適用対象外になる点も試験頻出の注意点として押さえておく。

## 共通の始め方

```bash
cd iam-permissions-boundary   # 対象モジュールに移動
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集して必要な値を設定
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```

各モジュールに必要な変数（`learner_account_id` 等）は 00_Baseline の outputs から取得できる。

```bash
cd ../../00_Baseline
terraform output
```
