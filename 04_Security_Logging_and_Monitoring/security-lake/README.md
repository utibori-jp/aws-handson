## Security Lake と IaC（Terraform）の相性について

Amazon Security Lake は Terraform で管理する際に特有の難しさがある。
Security Lake が裏側で多くのリソースを自動作成・自動管理しており、その挙動が Terraform の state に反映されないためだ。

`terraform apply` 後にデータが取り込まれない・Athena クエリが 0 件になるといった問題が発生した場合、必ずしも設定ミスとは限らない。
トラブルが発生した場合は [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) を参照すること。

---

### Security Lake が裏側で自動的に行うこと

`aws_securitylake_data_lake` を作成すると、Terraform の定義に含まれない以下のリソースが AWS 側で自動作成・管理される。

**S3 バケット**

`aws-security-data-lake-<region>-<random>` という命名規則で自動作成される。Terraform の state には含まれないため `terraform destroy` では削除されず、手動削除が必要。

**Glue Database / Glue Table**

ログソースごとに Glue Database（`amazon_security_lake_glue_db_<region>`）と Glue Table が Apache Iceberg 形式で自動作成される。Iceberg テーブルは S3 上に parquet ファイルが存在していても、Iceberg メタデータ（`.metadata.json`）のスナップショットにコミットされるまで Athena からは見えない。

**内部 ETL パイプライン**

CloudTrail 等のログソースから OCSF 形式への変換・parquet 書き込み・Iceberg メタデータへのコミットを行う内部パイプラインが自動構成される。初回データが Athena から参照可能になるまで数時間〜最大 24 時間以上かかることがある。

**サービスリンクロール（SLR）**

`AWSServiceRoleForSecurityLake` の他に `AWSServiceRoleForSecurityLakeResourceManagement` が自動作成されることがある。この SLR には KMS キーへのアクセス権限が必要だが、自動作成時にキーポリシーへの追加は行われない。

**Lake Formation 権限**

Glue Database / Table へのアクセス制御が Lake Formation の権限モデルで管理される。`terraform destroy` → 再 `apply` を繰り返すと、前回の残骸が Lake Formation の権限モデルにより不可視の状態で残り、再作成に失敗するケースがある（詳細は [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) を参照）。
