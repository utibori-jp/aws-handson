# 01 Identity and Access Management

## 概要

IAM のコアコンセプトを Terraform で実装し、手を動かして理解する章。
SCS 試験で頻出の「最小権限・権限委譲・外部アクセス検出・予防的コントロール」をカバーする。

## モジュール一覧

| モジュール | 学習テーマ | 前提 |
|---|---|---|
| [iam-permissions-boundary](iam-permissions-boundary/) | 権限境界 (Permissions Boundary) | 単一アカウント |
| [iam-access-analyzer](iam-access-analyzer/) | IAM Access Analyzer による外部アクセス検出 | 単一アカウント |
| [cross-account-role](cross-account-role/) | クロスアカウントロール + 信頼ポリシー | 2アカウント |
| [organizations-scp](organizations-scp/) | Service Control Policy (SCP) による予防的コントロール | Organizations 管理アカウント |

## 前提条件マトリクス

| モジュール | 単一アカウント | 2アカウント | Organizations管理 |
|---|---|---|---|
| iam-permissions-boundary | ✅ apply 可 | — | — |
| iam-access-analyzer | ✅ apply 可 | — | — |
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

`iam-permissions-boundary` は 00_Baseline の learner メンバーアカウント・SSO PermissionSet と連携できる。

| 状況 | 検証方法 |
|---|---|
| 00_Baseline apply 済み | learner-admin PermissionSet に境界をアタッチ。AdministratorAccess でも IAM 昇格が拒否されることを確認 |
| 00_Baseline なし | developer ロール（フォールバック）に AssumeRole して確認 |

00_Baseline の output（`sso_instance_arn` / `learner_admin_permission_set_arn`）を `terraform.tfvars` に渡すことで連携が有効になる。
