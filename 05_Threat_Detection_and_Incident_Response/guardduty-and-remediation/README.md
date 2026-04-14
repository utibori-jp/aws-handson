# guardduty-and-remediation

**前提**: learner アカウント（VPC 不要）

## このモジュールで試したいこと

GuardDuty を軸に「検知 → 自動修復」のパイプラインを Terraform で一から組み上げ、
SCS 試験で頻出の「いつ GuardDuty を使うか・いつ CloudTrail + EventBridge を使うか」の
判断基準を手を動かして体得する。

修復 Lambda は 4 本あり、**検知起点が 2 種類**ある。この使い分けが SCS の核心。

| 検知起点 | 特性 | 向いているシナリオ |
|---|---|---|
| CloudTrail → EventBridge | API 呼び出しの瞬間に発火（遅延なし） | 設定の危険操作（削除・全開放）を即座に差し戻す |
| GuardDuty → EventBridge | 振る舞い分析 → finding 発行（最大 15 分遅延） | 攻撃者の行動パターン（不正キー利用・C2 通信）に対応する |

## 4 つのハンズオンパターン

### パターン 1 — KMS キー削除予約 → 自動キャンセル（CloudTrail 起点）

`ScheduleKeyDeletion` API を EventBridge でキャッチし、`cancel-kms-deletion` Lambda が
`CancelKeyDeletion + EnableKey` を即時実行する。

**試すこと**: テスト用 KMS キーを作って削除予約を実行し、Lambda ログで自動キャンセルを確認する。
詳細なコマンドは `eventbridge.tf` の `【確認ポイント】1` を参照。

### パターン 2 — SG 全開放 → 危険ルール自動取り消し（CloudTrail 起点）

`AuthorizeSecurityGroupIngress` を EventBridge でキャッチし、`revoke-sg-ingress` Lambda が
`0.0.0.0/0` または `::/0` のルールを取り消す。

EventBridge ではフィルタできない IPv4/IPv6 の判定は Lambda 側で行う。
このパターンは「フィルタは広く取り Lambda でロジックを持つ」設計の典型例。

**試すこと**: テスト用 SG を作り全開放ルールを追加し、Lambda ログで自動取り消しを確認する。
詳細なコマンドは `eventbridge.tf` の `【確認ポイント】2` を参照。

### パターン 3 — IAM 認証情報の不正利用 → アクセスキー無効化（GuardDuty 起点）

GuardDuty の `UnauthorizedAccess:IAMUser/*` 等の finding を EventBridge でキャッチし、
`remediate-iam-key` Lambda が対象ユーザーのアクセスキーを即座に無効化する。

「侵害されたキーを止める」というインシデントレスポンスの定番手順を自動化したパターン。

**試すこと**: `create-sample-findings` で IAM 系 finding を生成し、finding 発行（最大 15 分待ち）→
（※Lambda 実行を Lambda ログで確認する。サンプルはダミーユーザーのため `not_found` になる。
詳細なコマンドは `guardduty.tf` の `【確認ポイント】2` を参照。）

### パターン 4 — EC2 の不正通信 → ネットワーク隔離（GuardDuty 起点）

GuardDuty の `CryptoCurrency:EC2/*`・`Backdoor:EC2/*` 等の finding を EventBridge でキャッチし、
`isolate-ec2` Lambda がインスタンスに隔離 SG（全トラフィック拒否）をアタッチして既存 SG を外す。

**Terminate ではなく Isolate する理由**: インスタンスを終了するとメモリ・プロセス情報が失われ、
フォレンジック調査の証拠が消える。隔離はインスタンスを生かしたまま通信を遮断し、
後から snapshot 取得や SSM セッションによる調査を可能にする（SCS 頻出の観点）。

**試すこと**: `create-sample-findings` で EC2 系 finding を生成し、finding 発行 →
（※Lambda 実行を Lambda ログで確認する。サンプルのダミーインスタンス ID は存在しないため `not_found` になる。
詳細なコマンドは `guardduty.tf` の `【確認ポイント】3` を参照。）

## 始め方

```bash
cd 05_Threat_Detection_and_Incident_Response/guardduty-and-remediation
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（aws_profile / alert_email を設定）
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```
