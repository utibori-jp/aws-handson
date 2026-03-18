# 前提知識

このリポジトリを使う前に押さえておくと理解がスムーズになる概念をまとめています。
詳細は各リンク先を参照してください。

---

## AWS アカウントとは

IAM ユーザーとは別の概念です。
AWS アカウントは「課金・リソース管理の単位」であり、1つのアカウントの中に IAM ユーザーやロールが存在します。

```
AWS アカウント（課金・リソースの境界）
  ├── IAM ユーザー（長期クレデンシャルを持つ人間/アプリ）
  ├── IAM ロール（一時クレデンシャルを発行する「帽子」）
  └── リソース（EC2, S3, Lambda, ...）
```

企業では「本番アカウント」「開発アカウント」のように用途ごとにアカウントを分けるのが一般的です。
分ける理由は「本番と開発を混在させない」だけでなく、**セキュリティ・ガバナンス上の境界を引くため**でもあります。
たとえば「監査ログ専用アカウント」や「セキュリティ監視アカウント」を独立させることで、
アプリ開発者が誤ってログを改ざんするリスクを排除したり、
セキュリティチームだけが閲覧できる領域を作ることができます。
このリポジトリもその構成を前提にしており、章ごとに監査・アクセス管理・セキュリティ監視などの用途別アカウントを扱います。

---

## AWS Organizations とは

複数のアカウントを一元管理するサービスです。
「管理アカウント（root）」が子アカウント（メンバーアカウント）を束ねます。

- 課金の一括管理
- SCP（Service Control Policy）による組織全体へのガードレール設定
- 新しいメンバーアカウントの払い出し（このリポジトリではこれを Terraform で行っています）

---

## IAM Identity Center とは

組織の「入口」を一本化するサービスです。
以前は AWS SSO と呼ばれていました。

従来の構成（Identity Center なし）では、アカウントをまたぐたびに IAM ユーザーを作成して
アクセスキーを管理する必要があり、クレデンシャルの管理が煩雑になります。

```
# 従来（Identity Center なし）
管理アカウント用 IAM ユーザー
開発アカウント用 IAM ユーザー  ← アカウントごとに別々に管理
本番アカウント用 IAM ユーザー

# Identity Center あり
Identity Center ユーザー 1つ
  ├── 管理アカウントへのアクセス（許可セットで制御）
  ├── 開発アカウントへのアクセス
  └── 本番アカウントへのアクセス
```

Identity Center 経由のアクセスは**一時クレデンシャル**（IAM ロールの AssumeRole）を使うため、
長期アクセスキーを各アカウントに作り回す必要がありません。

---

## IAM ロールと AssumeRole

ロールは「帽子」に例えられます。人やサービスが一時的に被ることで、その権限が付与されます。

- `aws sso login` をすると、裏では Identity Center が IAM ロールを AssumeRole して一時クレデンシャルを発行しています
- Terraform が `terraform-sso` プロファイルでリソースを作成できるのはこの仕組みによるものです
- EC2 インスタンスプロファイルや Lambda の実行ロールも同じ仕組みです

---

## このリポジトリの前提構成との対応

setup.md の「環境の全体像」と上記の概念の対応は以下のとおりです。

| setup.md の用語 | 実体 |
|---|---|
| 管理アカウント | Organizations の root アカウント |
| terraform-sso ユーザー | Identity Center のユーザー（管理アカウントの AdministratorAccess ロールを AssumeRole） |
| learner アカウント | Organizations のメンバーアカウント（Terraform で払い出す） |
| learner-admin / learner-readonly | learner アカウント内の IAM ロール（Identity Center 許可セットとして定義） |

---

## もっと詳しく知りたい場合

- [AWS Organizations とは - AWS ドキュメント](https://docs.aws.amazon.com/ja_jp/organizations/latest/userguide/orgs_introduction.html)
- [IAM Identity Center とは - AWS ドキュメント](https://docs.aws.amazon.com/ja_jp/singlesignon/latest/userguide/what-is.html)
- [IAM ロールの概念 - AWS ドキュメント](https://docs.aws.amazon.com/ja_jp/IAM/latest/UserGuide/id_roles.html)
