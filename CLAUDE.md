# CLAUDE.md — このリポジトリでの作業ルール

AWS SCS（Security Specialty）試験対策ハンズオン。
Terraform で AWS セキュリティリソースを実装し、手を動かして学ぶ構成。

## ディレクトリ構成

```
00_Baseline/          # 共通インフラ（VPC / CloudTrail / Organizations）。フラット構成。
01_Identity.../       # 以降の章。各モジュールが独立した Terraform root を持つサブディレクトリ構成。
  README.md           # 章レベルの概要・各モジュールの学習ポイント・共通の始め方
  iam-permissions-boundary/
  iam-access-analyzer/
  cross-account-role/
  ...
```

## README.md の配置ルール

- **モジュール単位の README.md は置かない**。
- 検証手順・学習ポイント・前提条件はドメインファイル（`iam.tf` / `trust_policy.tf` 等）のヘッダコメントに書く。
- 章ルートの `README.md` には「この章で何が学べるか」と「共通の始め方」を書く。
- 例外: 特殊なワークフロー（plan-only など）があるモジュールは README.md を置いてよい。

### 章ルート README.md の書き方

お手本: `02_Infrastructure_Security/README.md`

**構成（この順で書く）**

1. **`# 章名`** — 章タイトル
2. **`## 概要`** — この章がカバーする SCS 試験領域を 2〜3 行
3. **`## モジュール名`**（モジュールごとにセクション）
   - `**前提**: ...` — アカウント要件と VPC の要否を 1 行で
   - 本文 — 「何を学ぶか・なぜ重要か」を 2〜4 文で説明する。リソース名の列挙ではなく、**SCS 的な観点（攻撃シナリオ・制御の意味・落とし穴）** を中心に書く
4. **`## ローカル環境の前提条件`** — session-manager-plugin 等、章をまたぐセットアップが必要な場合のみ
5. **`## 共通の始め方`** — terraform.tfvars のコピー〜apply〜destroy の最小手順

**書き方のルール**

- 前提条件マトリクスは書かない（各モジュールセクションの冒頭 1 行で十分）
- テーブルは使わない（学習ポイントは文章で書く）
- 詳細な確認コマンドは書かない（ドメインファイルの `【確認ポイント】` に任せる）

## Terraform コーディング規約

- `required_version = ">= 1.5.0"`（Terraform / OpenTofu 両対応のため。`>= 1.14.0` にしない）
- `data "aws_partition"` は使わず `"aws"` で固定し `locals` に定義する
- `data "aws_caller_identity"` と `locals { account_id, partition }` は複数ファイルで参照するため `main.tf` に集約する
- プロバイダの認証は AWS SSO プロファイル（`terraform-sso`）を使用。メンバーアカウントへのデプロイは `assume_role { OrganizationAccountAccessRole }` で切り替える

### アカウント構成とプロファイル

このリポジトリは3アカウント構成を前提とする。

| アカウント | プロファイル | 役割 |
|---|---|---|
| 管理アカウント | `terraform-sso` | Terraform 実行専用。ハンズオンリソースは置かない |
| Learner アカウント | `learner-admin` / `learner-readonly` | ハンズオンのリソース配置先・実験先（標準） |
| Peer アカウント | `learner-admin` / `learner-readonly` | クロスアカウントシナリオの対向アカウント |

`learner-admin` / `learner-readonly` は IAM Identity Center で Learner・Peer 両アカウントに割り当てられているため、同一プロファイルでどちらのアカウントにもアクセスできる。

**リソース配置先の原則**
- 原則：リソースは Learner アカウントに置く（`assume_role` を使う）
- クロスアカウントシナリオ：Learner アカウントと Peer アカウントにリソースを分散させる（二重 provider パターン。`01_Identity_and_Access_Management/cross-account-role/main.tf` 参照）
- 管理アカウントにリソースを置くのは、CloudTrail 集約バケット等、意図的に管理アカウントへの配置が必要なリソースのみ

**二重 provider 構成時の注意**
- `data "aws_caller_identity"` はデフォルト provider（Learner アカウント）で実行される
- キーポリシーや信頼ポリシーに使う ARN がどのアカウントのものになるかを意識する

## コメントスタイル・モジュール構成

新しいモジュールを作るときは以下の既存モジュールをお手本にすること。

| 参照先 | お手本にする点 |
|---|---|
| `01_Identity_and_Access_Management/iam-permissions-boundary/iam.tf` | ファイルヘッダの書き方（概念説明・前提条件・確認手順をヘッダにまとめるパターン） |
| `01_Identity_and_Access_Management/iam-access-analyzer/access_analyzer.tf` | リソースブロックへのインラインコメントの粒度・書き方 |
| `01_Identity_and_Access_Management/iam-access-analyzer/main.tf` | `main.tf` のシンプルなヘッダと単一 `assume_role` プロバイダ構成 |
| `01_Identity_and_Access_Management/iam-access-analyzer/variables.tf` | 変数の description 形式（`"... (from 00_Baseline: terraform output xxx)"` パターン） |
| `01_Identity_and_Access_Management/cross-account-role/main.tf` | 二重 provider 構成（Learner アカウント + Peer アカウントにリソースを分散させるパターン） |

### ヘッダーコメント（全 .tf ファイル必須）
ファイル先頭に `# ===...===` 形式のヘッダーを入れる。
必ず含めるもの：「このファイルが何をするか」（1〜3行）

以下は内容があれば書く（空セクションは省略する）：
- `【...とは】` 形式の概念説明 — そのファイルで初出の概念、SCS的に重要なもの
- `【前提条件】` — 他モジュールの output が必要な場合など
- `【確認ポイント】` — apply 後に手を動かして確認できる操作がある場合、CLI コマンド付きで。複数アカウントにまたがる操作は `[管理アカウント]` / `[Learner アカウント]` ラベルを各手順の先頭につける

### インラインコメント
各リソースブロックに「なぜこの設定か」を添える。
余裕があれば「本番との違い」「SCS 的観点」も。

### 共通
- コメントは日本語

## Git / コミット規約

- Conventional Commits を使用。スコープは `(ディレクトリ/コンポーネント名)` 形式
  - 例: `feat(00_Baseline/cloudtrail)`, `refactor(01_Identity_and_Access_Management/iam-permissions-boundary)`
- コミットメッセージは**英語**、タイトル1行のみ（本文・箇条書き不要）
- `Co-Authored-By:` は付けない

## terraform.tfvars の管理

- 各モジュールに `terraform.tfvars.example` を置く。
- `terraform.tfvars.example` の書き方：
  - 先頭にコピー手順とコミット禁止を記載
  - 変数の取得元（`00_Baseline` の output コマンドなど）をコメントで示す
  - 省略可能な変数はコメントアウトして残す（省略時の挙動も説明する）
  - 参考：`iam-access-analyzer/terraform.tfvars.example`
- `terraform.tfvars`（実際の値が入るファイル）は `.gitignore` 対象。コミットしない。

## outputs.tf の管理

- ARN・ID・Name など、他の作業や CLI コマンドで参照する識別情報のみ記載する
- 確認コマンドは `outputs.tf` に書かない。ドメインファイルの `【確認ポイント】` に書く

## 設計方針

- 過剰な設計・不要なリソースは作らない（例: Terraform 実行専用ロールは不要と判断して削除済み）
- モジュールごとに独立した `terraform.tfstate`。他モジュールに影響を与えずに `destroy` できる構成を維持する
