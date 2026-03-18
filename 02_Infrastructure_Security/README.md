# 02 Infrastructure Security

## 概要

インフラレベルのセキュリティコントロールを Terraform で実装し、手を動かして理解する章。
SCS 試験で頻出の「ネットワーク境界防御・エッジ保護・コンテナセキュリティ」をカバーする。

## モジュール一覧

| モジュール | 学習テーマ | 前提 |
|---|---|---|
| [vpc-endpoint-gateway](vpc-endpoint-gateway/) | VPC Gateway Endpoint + エンドポイントポリシー | 単一アカウント + 00_Baseline VPC |
| [cloudfront-waf-oac](cloudfront-waf-oac/) | CloudFront OAC + WAF + セキュリティヘッダー | 単一アカウント |
| [ecs-fargate-security](ecs-fargate-security/) | ECS Fargate タスクロール最小権限 + readonlyRootFilesystem | 単一アカウント + 00_Baseline VPC |

## 前提条件マトリクス

| モジュール | 単一アカウント | 00_Baseline VPC 必要 |
|---|---|---|
| vpc-endpoint-gateway | ✅ apply 可 | ✅（var.vpc_id / var.route_table_ids を渡す） |
| cloudfront-waf-oac | ✅ apply 可 | 不要 |
| ecs-fargate-security | ✅ apply 可 | ✅（var.vpc_id / var.private_subnet_ids を渡す） |

## 共通の始め方

```bash
cd vpc-endpoint-gateway   # 対象モジュールに移動
terraform init
terraform plan
terraform apply
# 実験後
terraform destroy
```

## 00_Baseline からの値の取得

vpc-endpoint-gateway と ecs-fargate-security は 00_Baseline の VPC を使用する。
apply 時に以下のように値を渡す。

```bash
# 00_Baseline の outputs を確認
cd ../../00_Baseline
terraform output

# 取得した値を変数として渡す
cd ../02_Infrastructure_Security/vpc-endpoint-gateway
terraform apply \
  -var="vpc_id=vpc-xxxxxxxxxxxxxxxxx" \
  -var='route_table_ids=["rtb-xxxxxxxxxxxxxxxxx","rtb-yyyyyyyyyyyyyyyyy"]'
```
