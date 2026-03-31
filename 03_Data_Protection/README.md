# 03 Data Protection

## 概要

データ保護のコアコントロールを Terraform で実装し、手を動かして理解する章。
SCS 試験で頻出の「Object Lock（WORM）・CMK キーポリシー・職務分離」をカバーする。

## モジュール一覧

| モジュール | 学習テーマ | 前提 |
|---|---|---|
| [s3-object-lock-governance](s3-object-lock-governance/) | S3 Object Lock Governance モード + WORM ストレージ | 単一アカウント（destroy に注意） |
| [kms-cmk-encryption](kms-cmk-encryption/) | KMS CMK + キーポリシー職務分離 + SSE-KMS | 単一アカウント |
| [acm-tls-encryption](acm-tls-encryption/) | ACM インポート証明書（自己署名）・マネージド証明書との対比・ALB HTTP→HTTPS リダイレクト・TLS ポリシー選択 | 単一アカウント（ドメイン不要） |

## 前提条件マトリクス

| モジュール | 単一アカウント | 依存 |
|---|---|---|
| s3-object-lock-governance | ✅ apply 可 | なし（destroy 前に手動削除が必要な場合あり） |
| kms-cmk-encryption | ✅ apply 可 | なし |
| acm-tls-encryption | ✅ apply 可 | なし（ドメイン・Route 53 不要） |

## 共通の始め方

```bash
cd s3-object-lock-governance   # 対象モジュールに移動
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```

## s3-object-lock-governance の destroy 手順

Object Lock が有効なバケットは `force_destroy = true` でも、**retention 期間内のオブジェクトは削除できない**。
Governance モードの場合、`s3:BypassGovernanceRetention` 権限があれば手動削除できる。

```bash
# 1. バケット内のオブジェクト一覧とバージョン情報を確認
BUCKET="scs-handson-object-lock"
aws s3api list-object-versions --bucket "${BUCKET}"

# 2. Governance モードをバイパスしてオブジェクトを削除
#    （--bypass-governance-retention フラグが必要）
aws s3api delete-object \
  --bucket "${BUCKET}" \
  --key "demo/protected-file.txt" \
  --version-id "<VERSION_ID>" \
  --bypass-governance-retention

# 3. すべてのオブジェクト・バージョン・削除マーカーを削除してから destroy を実行
terraform destroy
```

> **Compliance モードとの違い**
> Governance モード：`s3:BypassGovernanceRetention` 権限を持つ管理者は削除できる。
> Compliance モード：**誰も**（アカウントルートも含む）retention 期間内は削除できない。
> 本ハンズオンでは Governance モードを使用しており、誤操作時の回復が可能。

