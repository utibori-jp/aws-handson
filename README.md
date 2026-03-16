# AWS SCS Hands-on via Terraform

このリポジトリは、AWS認定セキュリティ - スペシャリティ（SCS）の試験対策を主目的としたハンズオン集です。
SCSを受験してみたさい、参考書を読んでもイメージが湧きにくく苦労したという経験から、同じような課題感を抱える人の助けになればと思いこのレポジトリを作りました。Terraformを用いて実際にリソースを構築し、わざとアラートを発火させるなどの「実験」を通じて、AWSセキュリティの理解を深めることを目指しています。

## 本リポジトリの思想

### 1. 「動かして学ぶ」

SCSは概念的な理解が求められる試験ですが、画面上の設定だけでは記憶に定着しづらいです。本リポジトリでは、あえて「危険な設定」をデプロイし、それをAWSの各種サービスがどう検知し、どう自動修復するかを実験してみることに重点を置いています。

### 2. なぜ Terraform なのか

試験対策としてはCloudFormationが標準的ですが、本リポジトリではあえてTerraformを採用しています。

* **業界標準のスキル**: 現代のインフラ開発においてデファクトスタンダードであるTerraformに触れながら学ぶことで、試験合格後の実務に直結するスキルが得られます。
* **高い可読性と柔軟性**: 宣言的な記法により、リソース同士の依存関係が理解しやすく、概念の学習を妨げません。
* **マルチ環境への適応**: Terraformを通じた設計思考は、AWS以外の環境でも通用する「汎用的なセキュリティ設計能力」を養います。

### 3. コストとリスクについて

* **Low Cost Design**: NAT Gateway等の時間課金が発生するリソースを極力排除し、個人開発環境でも負担が少ない構成を意識しています。
* **自己責任の原則**: 学習後は必ず `terraform destroy` を実行してください。リソースの消し忘れによる高額請求について、本リポジトリは一切の責任を負いません。「破壊までがハンズオン」という意識で取り組んでください。

## はじめに

環境構築には、AWS IAM Identity Centerを用いた認証が必要です。

* **[環境セットアップ手順](https://www.google.com/search?q=./docs/setup.md)**

## ハンズオン構成

SCSの各ドメインに基づき、以下のセクションで構築・検証を行います。

* **[00. Baseline](https://www.google.com/search?q=./00_Baseline)**: VPCやCloudTrailなど、すべての検証の土台となるインフラの構築。
* **[01. IAM](https://www.google.com/search?q=./01_Identity_and_Access_Management)**: AssumeRole、権限境界、SCPを用いた「ガードレール」の構築。
* **[02. Infrastructure](https://www.google.com/search?q=./02_Infrastructure_Security)**: WAFやVPCエンドポイントを用いた「多層防御」の実装。
* **[03. Data Protection](https://www.google.com/search?q=./03_Data_Protection)**: KMSとS3を用いた「データの暗号化」と改ざん防止。
* **[04. Monitoring](https://www.google.com/search?q=./04_Security_Logging_and_Monitoring)**: GuardDuty等の検知系サービスを用いた「アラート発火実験」。
* **[05. Incident Response](https://www.google.com/search?q=./05_Threat_Detection_and_Incident_Response)**: ConfigやLambdaを用いた「自動修復（Auto Remediation）」の実装。
* **[06. Zero Trust](https://www.google.com/search?q=./06_Zero_Trust_Architecture)**: Verified Access等を用いた、境界に依存しない「次世代のアクセス制御」。
