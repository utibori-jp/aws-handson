# 05 Threat Detection and Incident Response

## 概要

脅威の検知・分類・自動インシデントレスポンスを Terraform で実装し、手を動かして理解する章。
SCS 試験で頻出の「GuardDuty による振る舞い検知」「Macie による機密データ分類」「EventBridge + Lambda による自動修復」をカバーする。

## guardduty-and-remediation

**前提**: learner アカウント（VPC 不要）

GuardDuty は CloudTrail・VPC Flow Logs・DNS ログを自動的に分析し、「振る舞いの異常」（不正な IAM 認証情報の使用・C2 通信・暗号通貨マイニング等）を検知する。このモジュールでは検知設定と自動修復を一体で構築する。

カスタム ThreatIntelSet（既知悪性 IP リスト）と IPSet（誤検知除外リスト）を S3 に配置して GuardDuty に登録することで、AWS 標準の脅威インテリジェンスに加えて自組織固有の検知精度向上を体験する。

自動修復は 2 つの検知起点を使い分ける。**CloudTrail 起点**では KMS キー削除予約・SG 全開放（0.0.0.0/0）という「設定の危険操作」を発生した瞬間に検知して Lambda が即時差し戻す。**GuardDuty 起点**では侵害された IAM 認証情報の使用・EC2 の不正通信という「攻撃者の行動パターン」を受けて Lambda がキー無効化・ネットワーク隔離を実行する。EC2 は終了（Terminate）ではなく隔離（Isolate）することでフォレンジック調査に必要な証拠を保全する設計になっている（SCS 頻出の観点）。

## macie-sensitive-data

**前提**: learner アカウント（VPC 不要）

Macie は S3 オブジェクトの「内容」を機械学習でスキャンして機密データを静的に検出する。GuardDuty が「何が起きたか」を検知するのに対し、Macie は「何が入っているか」を分類する補完的なサービスで、SCS 試験では両者の役割の違いが頻出する。

このモジュールでは、クレジットカード番号・SSN（マイナンバー相当）等のダミー機密データを含む CSV ファイルを S3 に配置し、ONE_TIME スキャンジョブで Macie の finding 生成から EventBridge → SNS 通知までのパイプラインを体験する。マネージドデータ識別子（100 種類以上の組み込みパターン）により、コード不要で機密データを検出できることを確認する。

## 共通の始め方

```bash
cd guardduty-and-remediation   # 対象モジュールに移動
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集して aws_profile / alert_email を設定
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```

`aws_profile` には Learner アカウントへの権限を持つプロファイル（`learner-admin`）を設定する。
