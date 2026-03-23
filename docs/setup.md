# AWS SCS ハンズオン環境セットアップ

このリポジトリは AWS Organizations + IAM Identity Center が有効な環境を前提とします。
以下の手順でローカル環境と AWS の接続設定を行ってください。

---

## 環境の全体像

```
[管理アカウント]
  ├── IAM Identity Center（SSO）
  │     └── terraform-sso ユーザー ─── Terraform apply/destroy に使う
  └── Organizations
        └── learner アカウント ─────── ハンズオンの動作確認に使う
              ├── learner-admin      （コンソール操作・CLI操作あり）
              └── learner-readonly   （コンソール参照・CLI参照のみ）
```

Terraform コマンドは常に `terraform-sso` プロファイルで実行します。
learner アカウントは「実際に触って試す」検証専用です。

---

## 手順 1: AWS Organizations を有効化する

AWS マネジメントコンソールで Organizations を有効化し、管理アカウントを設定します。
すでに有効化済みの場合はスキップしてください。

## 手順 2: IAM Identity Center を有効化する

IAM Identity Center コンソールで以下を設定します。

1. IAM Identity Center を有効化
2. ハンズオン用ユーザー（terraform-sso として使うもの）を作成
3. 管理アカウントに対して作成したユーザーと許可セット（AdministratorAccess 相当）を割り当て

## 手順 3: AWS CLI をインストールし、terraform-sso プロファイルを設定する

```bash
aws configure sso --profile terraform-sso
```

入力項目（例）：

| 項目 | 値 |
|---|---|
| SSO session name | 任意（例: scs-handson） |
| SSO start URL | Identity Center のアクセスポータル URL |
| SSO region | Identity Center を有効化したリージョン |
| CLI default client Region | ap-northeast-1 |
| CLI default output format | json |
| CLI profile name | terraform-sso |

設定後、以下でログインできることを確認します。

```bash
aws sso login --profile terraform-sso
aws sts get-caller-identity --profile terraform-sso
```

## 手順 4: Terraform をインストールする

[Install Terraform | HashiCorp Developer](https://developer.hashicorp.com/terraform/install) を参照してください。

## 手順 5: 00_Baseline を apply する

`variables.tf` のデフォルト値を確認し、必要に応じて `terraform.tfvars` を作成します。

```hcl
# terraform.tfvars（例）
learner_account_email = "yourname+learner@gmail.com"  # 既存メアドのエイリアスでOK
sso_username          = "yourname@example.com"         # Identity Center のユーザー名
```

> **メールアドレスのヒント**: Organizations メンバーアカウントにはユニークなメールアドレスが必要です。
> Gmail などのエイリアス機能（`user+learner@gmail.com`）を使えば、
> terraform-sso 作成時のメアドに `+learner` を付けるだけで新規取得不要です。

```bash
cd 00_Baseline
terraform init
terraform plan
terraform apply
```

## 手順 6: learner アカウントの CLI プロファイルを設定する

`terraform apply` が完了すると learner アカウントが払い出されます。
Identity Center のアクセスポータルから learner アカウントが見えることを確認後、
以下で CLI プロファイルを設定します。

```bash
# 操作ありの検証用
aws configure sso --profile learner-admin

# 参照のみの検証用
aws configure sso --profile learner-readonly
```

設定後の確認：

```bash
aws sts get-caller-identity --profile learner-admin
```

---

## 各ハンズオンでの使い方

| やること | 使うプロファイル |
|---|---|
| `terraform apply` / `terraform destroy` | terraform-sso |
| コンソールでリソースを操作・確認 | Identity Center ポータルから learner-admin または learner-readonly |
| CLI でリソースを操作・確認 | `--profile learner-admin` または `--profile learner-readonly` |

各モジュールの CLI 検証コマンドはそれぞれのソースファイル（`iam.tf` 等）のコメントを参照してください。
