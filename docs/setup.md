# AWS SCS ハンズオン環境セットアップ

このリポジトリは、AWS認定セキュリティ - スペシャリティ（SCS）の試験対策として、各種リソースの構築をTerraformで体験するためのものです。
ハンズオンを開始する前に、以下の手順に従ってローカル環境とAWSの接続設定を行ってください。

---

## 目的

本ハンズオンでは、セキュリティのベストプラクティスに基づき、長期利用するIAMユーザーのアクセスキーは使用しません。
IAM Identity Center（旧AWS SSO）を利用した認証を採用し、一時的な認証情報を用いてTerraformを実行するモダンな構成を目指します。

## 0. Terraformのインストール

公式ドキュメントを参照し、OSに合わせたインストールを完了させてください。
[Install Terraform | HashiCorp Developer](https://developer.hashicorp.com/terraform/install)

## 1. 認証基盤の設定

AWSマネジメントコンソールで、以下のIdentity Center設定を完了させます。

* IAM Identity Centerを有効化
* ハンズオン用ユーザーの作成
* 使用するAWSアカウントに対し、作成したユーザーと許可セット（AdministratorAccess等）を割り当て

## 2. AWS CLIの設定

ターミナルで以下のコマンドを実行し、Identity Centerとローカル環境を紐付けます。

```bash
aws configure sso

```

入力項目（例）：

* SSO session name: 任意の名前
* SSO start URL: コンソールから取得したアクセスポータルURL
* SSO region: Identity Centerを有効化したリージョン
* SSO registration scopes: そのままEnter
* CLI default client Region: ap-northeast-1
* CLI default output format: json
* CLI profile name: 任意の名前（例: scs-handson）

## 3. ログイン

実際にリソースを作成する前に、必ず以下のコマンドを実行して認証を通してください。

```bash
aws sso login --profile <設定したプロファイル名>

```

## 4. Terraformコードの記述

各ディレクトリのproviderブロックでは、以下のようにプロファイル名を指定します。

```hcl
provider "aws" {
  region  = "ap-northeast-1"
  profile = "<設定したプロファイル名>"
}

```

## 5. 動作確認

```bash
terraform init
terraform plan

```

エラーが出ず、実行計画が表示されれば準備完了です。
