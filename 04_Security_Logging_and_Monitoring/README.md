# 04 Security Logging and Monitoring

## 概要

検出的コントロール（Detective Controls）を Terraform で実装し、手を動かして理解する章。
00〜03 章で積み上げた「予防的コントロール」から「**検出・監視**」へ移行する。
SCS 試験ドメイン 2「Security Logging and Monitoring（約 22%）」に対応する。

## モジュール一覧

| モジュール | 学習テーマ | 前提 |
|---|---|---|
| [guardduty-threat-detection](guardduty-threat-detection/) | GuardDuty 振る舞い検知 + EventBridge + SNS 通知 | 単一アカウント |
| [cloudwatch-metric-alarm](cloudwatch-metric-alarm/) | CIS ベンチマーク準拠のメトリクスフィルター + アラーム | 単一アカウント（Trail を内包） |
| [config-conformance-pack](config-conformance-pack/) | AWS Config + Conformance Pack による準拠評価 | 単一アカウント |
| [security-hub-aggregation](security-hub-aggregation/) | Security Hub による ASFF フィンディング一元集約 | 単一アカウント（モジュール1・3 の後推奨） |

## 前提条件マトリクス

| モジュール | 単一アカウント | 依存 | 備考 |
|---|---|---|---|
| `guardduty-threat-detection` | ✅ apply 可 | なし | GuardDuty 無料枠 30 日。超過後は課金注意 |
| `cloudwatch-metric-alarm` | ✅ apply 可 | なし | 独自 Trail を内包。CWLogs 配信まで数分かかる |
| `config-conformance-pack` | ✅ apply 可 | なし | Config 記録は課金対象。実験後に destroy 推奨 |
| `security-hub-aggregation` | ✅ apply 可 | モジュール1・3 推奨 | 先に有効化するとフィンディング集約の体験価値が高い |

## 共通の始め方

```bash
cd guardduty-threat-detection   # 対象モジュールに移動
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```

## 実装優先順位（SCS 試験対策）

1. **`cloudwatch-metric-alarm`** — CIS Benchmark のメトリクスアラームは SCS 最頻出
2. **`guardduty-threat-detection`** — フィンディング発火体験で「何が何を検知するか」を直感的に理解
3. **`config-conformance-pack`** — Config ルールの選択問題に直結
4. **`security-hub-aggregation`** — ASFF と一元集約の概念を体感（発展）
