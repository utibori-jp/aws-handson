# =============================================================================
# flowlogs.tf — vpc-flowlogs-athena
# VPC フローログを S3 に出力する設定。
#
# 【VPC フローログとは】
# VPC の ENI を通過するネットワークトラフィック（許可・拒否）を記録するサービス。
# ソース/デスティネーション IP、ポート、プロトコル、バイト数、許可/拒否 などが記録される。
# セキュリティグループや NACL のデバッグ、不審な通信の調査に使う（SCS 頻出）。
#
# 【出力先: S3 vs CloudWatch Logs】
# - S3: 大量ログの長期保管・Athena による SQL 分析に適する（本モジュールで採用）
# - CloudWatch Logs: リアルタイム検知・メトリクスフィルタとの連携に適する
#   （コスト高のため大量ログには不向き）
#
# 【カスタムフォーマット】
# デフォルトフォーマットに加え、vpc-id / subnet-id / az-id など拡張フィールドを追加。
# Athena でクエリする際に VPC・サブネット単位の絞り込みが可能になる。
# =============================================================================

# ---
# フローログ用 S3 バケット
# ---

resource "aws_s3_bucket" "flowlogs" {
  bucket        = "${var.project_name}-vpc-flowlogs"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-vpc-flowlogs"
  }
}

resource "aws_s3_bucket_public_access_block" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# VPC フローログサービスがバケットに書き込むためのバケットポリシー。
# フローログは delivery.logs.amazonaws.com サービスプリンシパルから書き込まれる。
data "aws_iam_policy_document" "flowlogs_bucket" {
  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.flowlogs.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flowlogs.arn}/AWSLogs/${local.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id
  policy = data.aws_iam_policy_document.flowlogs_bucket.json
}

locals {
  # カスタムフォーマット。デフォルトフィールド + 拡張フィールドを追加。
  # Athena テーブル定義と一致させる必要がある。
  # join() でリスト化することでフィールドの追加・削除を見やすくしている。
  flow_log_format = join(" ", [
    "$${version}",      # フローログのバージョン
    "$${account-id}",   # フローが発生した AWS アカウント ID
    "$${interface-id}", # トラフィックを記録した ENI の ID
    "$${srcaddr}",      # 送信元 IP アドレス
    "$${dstaddr}",      # 宛先 IP アドレス
    "$${srcport}",      # 送信元ポート番号
    "$${dstport}",      # 宛先ポート番号
    "$${protocol}",     # IANA プロトコル番号（6=TCP, 17=UDP など）
    "$${packets}",      # キャプチャ期間中のパケット数
    "$${bytes}",        # キャプチャ期間中のバイト数
    "$${start}",        # キャプチャ開始時刻（Unix タイムスタンプ）
    "$${end}",          # キャプチャ終了時刻（Unix タイムスタンプ）
    "$${action}",       # SG / NACL による許可(ACCEPT) または拒否(REJECT)
    "$${log-status}",   # ログの記録状態（OK / NODATA / SKIPDATA）
    # 拡張フィールド（VPC・サブネット・AZ 単位での Athena クエリ絞り込みに使う）
    "$${vpc-id}",
    "$${subnet-id}",
    "$${instance-id}",  # ENI に紐づく EC2 インスタンス ID（なければ "-"）
    "$${tcp-flags}",    # TCP フラグのビットマスク（SYN=2, ACK=16 など）
    "$${type}",         # トラフィックの種別（IPv4 / IPv6 / EFA）
    "$${pkt-srcaddr}",  # NATされている場合の元の送信元 IP
    "$${pkt-dstaddr}",  # NATされている場合の元の宛先 IP
    "$${region}",
    "$${az-id}",
    "$${sublocation-type}",
    "$${sublocation-id}",
  ])
}

# ---
# VPC フローログ
# ---

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL" # ACCEPT / REJECT / ALL。全トラフィックを記録する。
  iam_role_arn    = null  # S3 出力は IAM ロール不要（CloudWatch Logs 出力時のみ必要）。
  log_destination = aws_s3_bucket.flowlogs.arn

  # S3 出力を指定する。
  log_destination_type = "s3"

  # Parquet 形式で保存する。
  # デフォルトのテキスト形式より Athena のクエリが高速になりストレージコストも削減できる。
  destination_options {
    file_format        = "parquet"
    per_hour_partition = true # 時間ごとにパーティションを分けて Athena のスキャン量を削減する。
  }

  log_format = local.flow_log_format

  tags = {
    Name = "${var.project_name}-vpc-flowlogs"
  }
}
