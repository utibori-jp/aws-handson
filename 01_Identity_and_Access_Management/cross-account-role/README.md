# cross-account-role

## ⚠️ 前提条件

このモジュールは **2つの AWS アカウント** が必要。
単一アカウント環境では `terraform plan` まで実行でき、
リソース定義の確認・学習は可能だが `terraform apply` はできない。

| 環境 | 実行可否 |
|---|---|
| 単一アカウント | `terraform plan` のみ（provider 認証エラーが出た場合は対象 profile を同じアカウントに向ける） |
| 2アカウント（Organizations なし） | ✅ `terraform apply` 可 |

## 必要な準備

```bash
# ソースアカウント（ロールを引き受ける側）の SSO プロファイルを設定
aws configure sso --profile source-sso

# ターゲットアカウント（ロールが存在する側）の SSO プロファイルを設定
aws configure sso --profile target-sso
```

## 使い方

```bash
terraform init

# プロファイルを変数で上書きして実行
terraform plan \
  -var="source_profile=source-sso" \
  -var="target_profile=target-sso"

terraform apply \
  -var="source_profile=source-sso" \
  -var="target_profile=target-sso"
```

## 学習ポイント

### 2段階認証モデル

クロスアカウントアクセスには **2つのポリシーが両方** 必要：

1. **ターゲット側の信頼ポリシー**（`trust_policy.tf`）
   - 「ソースアカウントの誰かを信頼する」
2. **ソース側のアイデンティティポリシー**（`assume_role_policy.tf`）
   - 「このユーザー/ロールに AssumeRole を許可する」

どちらか一方だけでは AssumeRole できない（AND 条件）。

### apply 後の動作確認

```bash
# ターゲットアカウントのロールに AssumeRole する
aws sts assume-role \
  --role-arn <cross_account_role_arn> \
  --role-session-name handson-test \
  --profile source-sso

# 発行された一時認証情報を環境変数にセットして動作確認
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<SessionToken>

# ターゲットアカウントのリソースを ReadOnly で参照できることを確認
aws s3 ls
aws ec2 describe-instances
```
