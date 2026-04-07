# Security Lake Terraform 構築トラブルシューティング

## よくあるトラブルと原因

| 症状 | 考えられる原因 |
|------|---------------|
| S3 に parquet があるのに Athena で 0 件 | Iceberg のスナップショットにまだコミットされていない（ETL の実行待ち）。`.metadata.json` の `current-snapshot-id` が `-1` のままなら未コミット。 |
| `list-data-lake-exceptions` に KMS エラー | SLR（`AWSServiceRoleForSecurityLakeResourceManagement`）に対して KMS キーポリシーで必要な権限（`GenerateDataKey`, `Decrypt`, `DescribeKey` 等）が付与されていない。 |
| `list-data-lake-exceptions` に CloudTrail エラー | 組織の証跡（`IsOrganizationTrail: true`）が管理アカウントに作成されていない。 |
| `terraform destroy` 後の再 `apply` で FAILED | 前回の Glue Database / S3 バケットが残っている。後述の手順で手動削除が必要。 |
| 例外のタイムスタンプが更新されない | 対処済みでも例外の再評価には時間がかかる（数時間〜）。すぐに消えなくても問題ない場合がある。 |

## 調査手順

問題が発生した場合、以下の順序で調査することを推奨する。

```bash
# 1. Security Lake の例外を確認
aws securitylake list-data-lake-exceptions \
  --regions "ap-northeast-1" --profile learner-admin

# 2. Iceberg メタデータの状態を確認（スナップショットが空かどうか）
aws s3 ls s3://<security-lake-bucket>/aws/CLOUD_TRAIL_MGMT/2.0/metadata/ \
  --profile learner-admin

# 3. CloudTrail で KMS の AccessDenied を探す
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=kms.amazonaws.com \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --max-results 50 --profile learner-admin \
  --query 'Events[?contains(CloudTrailEvent, `AccessDenied`)].{Time:EventTime, Name:EventName, User:Username}' \
  --output table

# 4. Glue 関連のエラーを探す
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=glue.amazonaws.com \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --max-results 50 --profile learner-admin \
  --query 'Events[?contains(CloudTrailEvent, `AccessDenied`) || contains(CloudTrailEvent, `Error`)].{Time:EventTime, Name:EventName, User:Username}' \
  --output table

# 5. parquet データの存在確認
aws s3 ls s3://<security-lake-bucket>/aws/CLOUD_TRAIL_MGMT/2.0/ \
  --recursive --profile learner-admin | grep -v metadata
```

## ハンズオンがうまくいかない場合

上記のトラブルシューティングを試しても解決しない場合は、ソースコードとコメントを読んで Security Lake の仕組みを理解することをハンズオンのゴールとしてしてほしい。

Security Lake の Terraform 管理は本番環境でも苦労するポイントであり、以下のような学びが得られればこのモジュールとしては十分。

- Security Lake が裏側で何を自動作成するのか（S3・Glue・Lake Formation・SLR）
- Apache Iceberg テーブルの仕組み（スナップショットベースのメタデータ管理）
- KMS キーポリシーにおける SLR への権限付与の考え方
- Organizations の委任管理者モデルと Security Lake の関係
- マネージドサービスを IaC で管理する際の一般的な課題（state 外リソース、非同期処理、可観測性の低さ）

---

## createStatus: FAILED の解決記録

### 概要

Amazon Security Lake を Terraform で有効化する際、`aws_securitylake_data_lake` の作成が
`FAILED` になり続けた事象の原因調査と解決までの記録。

### 環境

- Terraform AWS Provider: ~> 6.0
- リージョン: ap-northeast-1
- アカウント構成: Organizations 委任管理者パターン（管理アカウント → learner アカウントへ委任）
- 認証: AWS IAM Identity Center（SSO）経由、AdministratorAccess 相当

### 事象

`terraform apply` で `aws_securitylake_data_lake.main` を作成すると、毎回
`createStatus: FAILED` になる。`terraform destroy` → 再 `apply` を繰り返しても同じ結果。

### 原因調査の経過

### 1. CloudTrail・Lambda ログの確認

CreateDataLake API 呼び出し自体は成功（INITIALIZED）しており、Lambda ログにも ERROR は出ていなかった。
CloudTrail に `CreateLogStream` の LogGroup 未存在エラーがあったが、初回のみで致命的ではなかった。

### 2. `list-data-lake-exceptions` で原因特定

```bash
aws securitylake list-data-lake-exceptions \
  --regions "ap-northeast-1" \
  --profile learner-admin
```

→ **「pre-existing Glue Database」** が原因と判明。

### 3. Glue Database の確認で矛盾に遭遇

```bash
aws glue get-databases --profile learner-admin
```

→ 空（データベースが存在しないように見える）。

しかし名前を直接指定すると：

```bash
aws glue get-database \
  --name "amazon_security_lake_glue_db_ap_northeast_1" \
  --profile learner-admin
```

→ `AccessDeniedException: Insufficient Lake Formation permission(s): Required Describe on amazon_security_lake_glue_db_ap_northeast_1`

**データベースは存在しているのに、権限不足で見えなかった。**

---

### 根本原因

原因は 2 つの要素が組み合わさったもの。

### 原因①: FAILED → destroy で残骸が残る

Security Lake は内部的に複数の AWS リソースを自動作成する（Glue Database、S3 バケット、Lake Formation 設定など）。
`createStatus: FAILED` の状態で `terraform destroy` を実行しても、これらの内部リソースは
Terraform 管理外のため完全にクリーンアップされない。

残骸として残っていたリソース：

- Glue Database: `amazon_security_lake_glue_db_ap_northeast_1`
- S3 バケット: `aws-security-data-lake-ap-northeast-1-*`
- Lake Formation DataLakeAdmins に MetaStoreManager ロールの残存

### 原因②: Lake Formation の権限モデルにより残骸が不可視

AWS には Glue データカタログへのアクセス制御が **2 層** ある。

| レイヤー | 状態 |
|---|---|
| IAM | AdministratorAccess → 全許可 |
| Lake Formation | Security Lake 内部ロールにのみ権限付与 → 自分のプリンシパルには未付与 |

Security Lake が Glue Database を作成する際、Lake Formation の権限を自身の内部ロール
（MetaStoreManager 等）にのみ付与する。`terraform destroy` 後もこの権限設定が残り、
Administrator 権限を持っていても Lake Formation レイヤーで拒否されるため、
Glue Database が「存在しないように見える」状態になっていた。

`get-databases`（一覧取得）では「あなたに見える DB がない」= 空リストが返り、
名前指定の `get-database` では `AccessDeniedException` が返る、という挙動の違いで矛盾が生じていた。

---

### 解決手順

### Step 1: Lake Formation Admin に自分を登録

Lake Formation Admin になることで、全 Glue リソースが可視化される。

このモジュールでは `lakeformation.tf` の `aws_lakeformation_data_lake_settings` で
Lake Formation Admin を Terraform 管理している。`terraform.tfvars` に
`lakeformation_admin_role_arn` を設定済みであれば、ターゲット指定 apply で登録できる。

```bash
terraform apply -target=aws_lakeformation_data_lake_settings.main
```

> **緊急時の代替（tfvars 未設定の場合）**
>
> SSO の一時クレデンシャル（`sts::assumed-role`）は登録できないため、元の IAM ロール ARN を使用する。
>
> ```bash
> # ロール ARN を確認
> aws iam list-roles --profile learner-admin \
>   --query "Roles[?contains(RoleName,'scs-handson-learner-admin')].Arn" \
>   --output text
>
> # Lake Formation Admin に登録
> aws lakeformation put-data-lake-settings \
>   --data-lake-settings '{"DataLakeAdmins":[{"DataLakePrincipalIdentifier":"<上記のロールARN>"}]}' \
>   --profile learner-admin
> ```

### Step 2: 自分に Glue Database への権限を付与

Lake Formation Admin でも、個別 DB への Drop 権限は別途必要。

```bash
aws lakeformation grant-permissions \
  --principal '{"DataLakePrincipalIdentifier":"<ロールARN>"}' \
  --resource '{"Database":{"Name":"amazon_security_lake_glue_db_ap_northeast_1"}}' \
  --permissions ALL \
  --permissions-with-grant-option ALL \
  --profile learner-admin
```

### Step 3: 残骸を削除

```bash
# Glue Database 削除（テーブルがあれば先に削除）
aws glue get-tables \
  --database-name "amazon_security_lake_glue_db_ap_northeast_1" \
  --profile learner-admin \
  --query 'TableList[].Name' \
  --output text

aws glue delete-database \
  --name "amazon_security_lake_glue_db_ap_northeast_1" \
  --profile learner-admin

# S3 バケット削除
aws s3 rm s3://aws-security-data-lake-ap-northeast-1-<suffix> --recursive --profile learner-admin
aws s3 rb s3://aws-security-data-lake-ap-northeast-1-<suffix> --profile learner-admin
```

> Lake Formation の DataLakeAdmins は Step 1 の `-target` apply で正しい状態に上書き済みのため、
> 手動クリーンアップは不要。

### Step 4: 更地確認

以下がすべて空/未存在であることを確認する。

```bash
# Security Lake が削除されていること
aws securitylake list-data-lakes \
  --regions ap-northeast-1 \
  --profile learner-admin

# Glue Database が削除されていること
aws glue get-database \
  --name "amazon_security_lake_glue_db_ap_northeast_1" \
  --profile learner-admin
# → EntityNotFoundException が返れば OK

# S3 バケットが削除されていること
aws s3 ls --profile learner-admin | grep security-data-lake

# Lake Formation Admin が SSO ロールのみになっていること（Step 1 で設定済み）
aws lakeformation get-data-lake-settings \
  --profile learner-admin \
  --region ap-northeast-1 \
  --query 'DataLakeSettings.DataLakeAdmins'
```

### Step 5: terraform apply

残骸がクリアされた状態で再実行。Security Lake が新しい Glue Database と S3 バケットを正常に作成する。

```bash
terraform apply
```
