# 05 Threat Detection and Incident Response

## 概要

04章「検出」から続く「**自動対応（Automated Response）**」を実装する章。
SCS 試験 Domain 1「Threat Detection and Incident Response（約 14%）」を中心にカバーする。

## モジュール一覧

| モジュール | 学習テーマ | 前提 |
|---|---|---|
| [guardduty-auto-remediation](guardduty-auto-remediation/) | GuardDuty フィンディング → Lambda 自動修復（IAM キー無効化 / EC2 隔離） | 単一アカウント ⚠️ 下記注意事項を読むこと |
| [secrets-manager-rotation](secrets-manager-rotation/) | Secrets Manager シークレット自動ローテーション（4フェーズ Lambda） | 単一アカウント |
| [macie-sensitive-data](macie-sensitive-data/) | Macie による S3 内 PII 自動検出 + EventBridge 通知 | 単一アカウント |

## ⚠️ guardduty-auto-remediation の前提条件

**04章の `guardduty-threat-detection` を apply 済みの場合は、先に destroy してからこのモジュールを apply すること。**

GuardDuty Detector は 1 リージョンに 1 つしか作成できない。
両モジュールを同時に apply すると `aws_guardduty_detector` の作成でエラーになる。

```bash
# 04章の GuardDuty を先に destroy する
cd ../../04_Security_Logging_and_Monitoring/guardduty-threat-detection
terraform destroy

# その後にこのモジュールを apply する
cd ../../05_Threat_Detection_and_Incident_Response/guardduty-auto-remediation
terraform apply
```

## 前提条件マトリクス

| モジュール | 単一アカウント | 依存 | 備考 |
|---|---|---|---|
| `guardduty-auto-remediation` | ✅ apply 可 | 04章 guardduty-threat-detection を先に destroy | GuardDuty Detector は 1 リージョンに 1 つ |
| `secrets-manager-rotation` | ✅ apply 可 | なし | apply 直後にローテーションが自動発動する |
| `macie-sensitive-data` | ✅ apply 可 | なし | スキャン完了まで数分〜十数分かかる |

## 共通の始め方

```bash
cd secrets-manager-rotation   # 対象モジュールに移動（推奨: secrets から開始）
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```

## 推奨実装順序

1. **`secrets-manager-rotation`** — 副作用が少なく、apply 直後にローテーションを確認できる
2. **`guardduty-auto-remediation`** — 04章との連続性が強い。Lambda 最小権限が SCS 核心テーマ
3. **`macie-sensitive-data`** — GuardDuty（動的検出）vs. Macie（静的データ検出）の対比として最後に
