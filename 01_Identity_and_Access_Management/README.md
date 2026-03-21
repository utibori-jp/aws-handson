# 01 Identity and Access Management

## 概要

IAM のコアコンセプトを Terraform で実装し、手を動かして理解する章。
SCS 試験で頻出の「最小権限・権限委譲・外部アクセス検出・予防的コントロール」をカバーする。

## モジュール一覧

| モジュール | 学習テーマ | 前提 |
|---|---|---|
| [iam-permissions-boundary](iam-permissions-boundary/) | 権限境界 (Permissions Boundary) | 00_Baseline 必須 |
| [iam-access-analyzer](iam-access-analyzer/) | IAM Access Analyzer による外部アクセス検出 | 00_Baseline 必須 |
| [cross-account-role](cross-account-role/) | クロスアカウントロール + 信頼ポリシー | 00_Baseline 必須（learner + peer） |
| [organizations-scp](organizations-scp/) | Service Control Policy (SCP) による予防的コントロール | Organizations 管理アカウント |

## 前提条件マトリクス

| モジュール | 00_Baseline なし | 00_Baseline あり | Organizations管理 |
|---|---|---|---|
| iam-permissions-boundary | plan のみ | ✅ apply 可 | — |
| iam-access-analyzer | plan のみ | ✅ apply 可 | — |
| cross-account-role | plan のみ | ✅ apply 可 | — |
| organizations-scp | plan のみ | plan のみ | ✅ apply 可 |

## 共通の始め方

各モジュールのサブディレクトリで独立して Terraform を実行する。

```bash
cd iam-permissions-boundary   # 対象モジュールに移動
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```

各モジュールは独立した `terraform.tfstate` を持つため、
他のモジュールに影響を与えずに個別に `destroy` できる。

## 00_Baseline との関係

`iam-permissions-boundary` は **00_Baseline が apply 済みであることが必須**。
learner-admin PermissionSet（AdministratorAccess）に境界を直接アタッチし、
「Admin 権限でも IAM 昇格操作は拒否される」ことを確認する。

00_Baseline の output から以下の値を取得して `terraform.tfvars` に設定すること。

```
sso_instance_arn                 = "<terraform output sso_instance_arn>"
learner_admin_permission_set_arn = "<terraform output learner_admin_permission_set_arn>"
```

`iam-access-analyzer` も **00_Baseline が apply 済みであることが必須**。
リソースは learner メンバーアカウントにデプロイされる。
`OrganizationAccountAccessRole` を経由して learner アカウントに切り替えるため、
`terraform-sso`（管理アカウント）プロファイルのまま実行できる。

00_Baseline の output から以下の値を取得して `terraform.tfvars` に設定すること。

```
learner_account_id = "<terraform output learner_account_id>"
```

`cross-account-role` も **00_Baseline が apply 済みであることが必須**。
learner アカウント（ソース）と peer アカウント（ターゲット）の2アカウントを使い、
クロスアカウントロールの信頼ポリシーとロールチェーンを実装する。

00_Baseline の output から以下の値を取得して `terraform.tfvars` に設定すること。

```
learner_account_id = "<terraform output learner_account_id>"
peer_account_id    = "<terraform output peer_account_id>"
```
