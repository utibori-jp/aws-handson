# organizations-scp

## ⚠️ 前提条件

このモジュールは **AWS Organizations の管理アカウント** が必要。
管理アカウントがない場合でも `terraform plan` で SCP の JSON ドキュメントを確認でき、
「どのような制御がかかるか」の学習は完結する。

| 環境 | 実行可否 |
|---|---|
| 単一アカウント（Organizations なし） | `terraform plan` のみ（学習目標は達成できる） |
| Organizations メンバーアカウント | `terraform plan` のみ |
| Organizations 管理アカウント | ✅ `terraform apply` 可 |

## SCP を plan で読む（管理アカウントがない場合）

```bash
terraform init
terraform plan -var="management_profile=terraform-sso"
```

`terraform plan` の出力に SCP ポリシー Document の JSON が表示される。
`scp_root_restriction.tf` と `scp_region_guardrail.tf` のコメントと合わせて
「なぜこの Statement が必要か」を確認する。

Organizations を後から有効化した際は、そのまま `terraform apply` を実行すれば
SCP が適用される構成になっている。

## 学習ポイント

### SCP の適用範囲

- SCP は **Organizations の管理アカウント自体には適用されない**（メンバーアカウントのみ）
- SCP は「許可の上限」であり、単体では何も許可しない（アイデンティティポリシーとの AND）
- `Deny` SCP を使うと、アカウント内の管理者でも特定操作を実行できなくなる

### ルートユーザー操作の制限

`scp_root_restriction.tf` では `aws:PrincipalArn` 条件でルートユーザーを特定し、
ほぼ全操作を Deny する。これにより「ルートユーザーは使わない」という組織ポリシーを
技術的にエンフォースできる。

### リージョンガードレール

`scp_region_guardrail.tf` では `aws:RequestedRegion` 条件で
`ap-northeast-1` 以外のリージョンへのリソース作成を Deny する。
IAM・STS・CloudFront などのグローバルサービスは除外条件に含める。

## 使い方（管理アカウントの場合）

```bash
terraform init

terraform apply \
  -var="management_profile=your-management-sso" \
  -var="target_ou_id=ou-xxxx-xxxxxxxx"
```
