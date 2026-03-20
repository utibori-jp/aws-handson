# CLAUDE.md — このリポジトリでの作業ルール

AWS SCS（Security Specialty）試験対策ハンズオン。
Terraform で AWS セキュリティリソースを実装し、手を動かして学ぶ構成。

## ディレクトリ構成

```
00_Baseline/          # 共通インフラ（VPC / CloudTrail / Organizations）。フラット構成。
01_Identity.../       # 以降の章。各モジュールが独立した Terraform root を持つサブディレクトリ構成。
  README.md           # 章レベルの共通説明・前提条件マトリクス
  iam-permissions-boundary/
  iam-access-analyzer/
  cross-account-role/
  ...
```

## README.md の配置ルール

- **モジュール単位の README.md は置かない**。
- 検証手順・学習ポイント・前提条件はドメインファイル（`iam.tf` / `trust_policy.tf` 等）のヘッダコメントに書く。
- 共通説明・前提条件マトリクスは章ルートの `README.md`（例: `01_Identity.../README.md`）に書く。
- 例外: `organizations-scp` のように「plan-only」など特殊なワークフローがあるモジュールは README.md を置いてよい。

## Terraform コーディング規約

- `required_version = ">= 1.5.0"`（Terraform / OpenTofu 両対応のため。`>= 1.14.0` にしない）
- `data "aws_partition"` は使わず `"aws"` で固定し `locals` に定義する
- `data "aws_caller_identity"` と `locals { account_id, partition }` は複数ファイルで参照するため `main.tf` に集約する
- プロバイダの認証は AWS SSO プロファイル（`terraform-sso`）を使用。メンバーアカウントへのデプロイは `assume_role { OrganizationAccountAccessRole }` で切り替える

## コメントスタイル・モジュール構成

新しいモジュールを作るときは以下の既存モジュールをお手本にすること。

| 参照先 | お手本にする点 |
|---|---|
| `01_Identity_and_Access_Management/iam-permissions-boundary/iam.tf` | ファイルヘッダの書き方（概念説明・前提条件・確認手順をヘッダにまとめるパターン） |
| `01_Identity_and_Access_Management/iam-access-analyzer/access_analyzer.tf` | リソースブロックへのインラインコメントの粒度・書き方 |
| `01_Identity_and_Access_Management/iam-access-analyzer/main.tf` | `main.tf` のシンプルなヘッダと `assume_role` プロバイダ構成 |
| `01_Identity_and_Access_Management/iam-access-analyzer/variables.tf` | 変数の description 形式（`"... (from 00_Baseline: terraform output xxx)"` パターン） |

基本ルール：
- ファイル先頭に `# ===...===` 形式のヘッダーコメントを入れる
- ヘッダーには「このファイルが何をするか」「重要な概念（`【...とは】` 形式）」「前提条件」「確認ポイント（CLI コマンド付き）」を書く
- 各リソースブロックに「なぜこの設定か」「本番との違い」「SCS 的観点」をインラインコメントで添える
- コメントは日本語で書く

## Git / コミット規約

- Conventional Commits を使用。スコープは `(ディレクトリ/コンポーネント名)` 形式
  - 例: `feat(00_Baseline/cloudtrail)`, `refactor(01_Identity_and_Access_Management/iam-permissions-boundary)`
- コミットメッセージは**英語**、タイトル1行のみ（本文・箇条書き不要）
- `Co-Authored-By:` は付けない

## 設計方針

- 過剰な設計・不要なリソースは作らない（例: Terraform 実行専用ロールは不要と判断して削除済み）
- モジュールごとに独立した `terraform.tfstate`。他モジュールに影響を与えずに `destroy` できる構成を維持する
