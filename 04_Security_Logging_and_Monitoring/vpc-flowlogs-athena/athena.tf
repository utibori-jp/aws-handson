# =============================================================================
# athena.tf — vpc-flowlogs-athena
# Athena データベース・テーブル・保存済みクエリを定義する。
#
# 【Athena による VPC フローログ分析】
# S3 に蓄積された Parquet 形式のフローログを Athena で SQL 分析する。
# 代表的なユースケース:
#   - 拒否トラフィック（REJECT）の一覧表示 → 侵害試行の把握
#   - 特定 IP からの通信確認 → 不審な外部アクセスの調査
#   - 大量データ転送の検出（bytes が大きい通信）→ データ漏洩の検知
#
# 【Athena の仕組み】
# Athena はサーバーレス SQL エンジン。S3 に置いたファイルをそのまま
# テーブルとして SQL でクエリできる（データ移動不要）。
# スキャンした分だけ課金されるため、パーティションで絞り込むことでコストを削減できる。
# =============================================================================

# ---
# Athena クエリ結果保存用 S3 バケット
# ---

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.project_name}-athena-results"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-athena-results"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---
# Athena ワークグループ
# ---

resource "aws_athena_workgroup" "flowlogs" {
  name = "${var.project_name}-flowlogs"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # クエリのスキャン上限（1GB）。意図しない大量スキャンでのコスト爆発を防ぐ。
    bytes_scanned_cutoff_per_query = 1073741824 # 1 GB
  }

  tags = {
    Name = "${var.project_name}-flowlogs"
  }
}

# ---
# Glue データベース（Athena はメタデータ管理に Glue Data Catalog を使う）
# ---

resource "aws_glue_catalog_database" "flowlogs" {
  name = replace("${var.project_name}_vpc_flowlogs", "-", "_")
}

# ---
# Glue テーブル（Athena テーブル定義）
# ---
# カスタムフォーマットで出力した Parquet ファイルのスキーマを定義する。
# flowlogs.tf の log_format と列の順序・型を一致させること。

resource "aws_glue_catalog_table" "flowlogs" {
  name          = "vpc_flow_logs"
  database_name = aws_glue_catalog_database.flowlogs.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification"       = "parquet"
    "parquet.compression"  = "SNAPPY"
    "projection.enabled"   = "true"
    # パーティションプロジェクションを使うことで MSCK REPAIR TABLE が不要になる。
    # S3 に新しいパーティションが追加されても Athena が自動的に認識する。
    "projection.year.type"  = "integer"
    "projection.year.range" = "2024,2030"
    "projection.month.type" = "integer"
    "projection.month.range" = "1,12"
    "projection.month.digits" = "2"
    "projection.day.type"   = "integer"
    "projection.day.range"  = "1,31"
    "projection.day.digits" = "2"
    "projection.hour.type"  = "integer"
    "projection.hour.range" = "0,23"
    "projection.hour.digits" = "2"
    "storage.location.template" = "s3://${aws_s3_bucket.flowlogs.bucket}/AWSLogs/${local.account_id}/vpcflowlogs/${var.region}/$${year}/$${month}/$${day}/$${hour}/"
  }

  partition_keys {
    name = "year"
    type = "int"
  }
  partition_keys {
    name = "month"
    type = "int"
  }
  partition_keys {
    name = "day"
    type = "int"
  }
  partition_keys {
    name = "hour"
    type = "int"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.flowlogs.bucket}/AWSLogs/${local.account_id}/vpcflowlogs/${var.region}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    # カスタム log_format の列定義（flowlogs.tf の log_format と順序を合わせる）。
    columns {
      name = "version"
      type = "int"
    }
    columns {
      name = "account_id"
      type = "string"
    }
    columns {
      name = "interface_id"
      type = "string"
    }
    columns {
      name = "srcaddr"
      type = "string"
    }
    columns {
      name = "dstaddr"
      type = "string"
    }
    columns {
      name = "srcport"
      type = "int"
    }
    columns {
      name = "dstport"
      type = "int"
    }
    columns {
      name = "protocol"
      type = "bigint"
    }
    columns {
      name = "packets"
      type = "bigint"
    }
    columns {
      name = "bytes"
      type = "bigint"
    }
    columns {
      name = "start"
      type = "bigint"
    }
    columns {
      name = "end"
      type = "bigint"
    }
    columns {
      name = "action"
      type = "string"
    }
    columns {
      name = "log_status"
      type = "string"
    }
    columns {
      name = "vpc_id"
      type = "string"
    }
    columns {
      name = "subnet_id"
      type = "string"
    }
    columns {
      name = "instance_id"
      type = "string"
    }
    columns {
      name = "tcp_flags"
      type = "int"
    }
    columns {
      name = "type"
      type = "string"
    }
    columns {
      name = "pkt_srcaddr"
      type = "string"
    }
    columns {
      name = "pkt_dstaddr"
      type = "string"
    }
    columns {
      name = "region"
      type = "string"
    }
    columns {
      name = "az_id"
      type = "string"
    }
    columns {
      name = "sublocation_type"
      type = "string"
    }
    columns {
      name = "sublocation_id"
      type = "string"
    }
  }
}

# ---
# 保存済みクエリ（Named Query）
# ---
# よく使う分析クエリをあらかじめ保存しておき、Athena コンソールから
# すぐに実行できるようにする。

# クエリ 1: 拒否トラフィックの一覧
resource "aws_athena_named_query" "rejected_traffic" {
  name      = "${var.project_name}-rejected-traffic"
  workgroup = aws_athena_workgroup.flowlogs.id
  database  = aws_glue_catalog_database.flowlogs.name

  query = <<-SQL
    -- 直近1時間の拒否トラフィック（上位 100 件）
    -- REJECT されたトラフィックは SG や NACL によるブロックを意味する。
    -- 同一送信元から大量の REJECT が来る場合はポートスキャンや侵害試行の可能性がある。
    SELECT
      srcaddr,
      dstaddr,
      srcport,
      dstport,
      protocol,
      packets,
      bytes,
      action,
      from_unixtime(start) AS start_time,
      vpc_id,
      subnet_id
    FROM "${aws_glue_catalog_database.flowlogs.name}"."vpc_flow_logs"
    WHERE
      action = 'REJECT'
      AND year  = year(current_date)
      AND month = month(current_date)
      AND day   = day(current_date)
    ORDER BY packets DESC
    LIMIT 100;
  SQL
}

# クエリ 2: 特定 IP からの通信を全件検索
resource "aws_athena_named_query" "traffic_by_src_ip" {
  name      = "${var.project_name}-traffic-by-src-ip"
  workgroup = aws_athena_workgroup.flowlogs.id
  database  = aws_glue_catalog_database.flowlogs.name

  query = <<-SQL
    -- 特定の送信元 IP アドレスからの通信を全件取得する。
    -- 不審な IP を GuardDuty などで検知した後に詳細調査するときに使う。
    -- WHERE の srcaddr を調査対象 IP に書き換えて実行すること。
    SELECT
      srcaddr,
      dstaddr,
      srcport,
      dstport,
      protocol,
      packets,
      bytes,
      action,
      from_unixtime(start) AS start_time,
      vpc_id,
      subnet_id,
      instance_id
    FROM "${aws_glue_catalog_database.flowlogs.name}"."vpc_flow_logs"
    WHERE
      srcaddr = '0.0.0.0'  -- ← 調査対象の IP アドレスに書き換える
      AND year  = year(current_date)
      AND month = month(current_date)
      AND day   = day(current_date)
    ORDER BY start_time DESC
    LIMIT 200;
  SQL
}

# クエリ 3: 大量データ転送の検出（データ漏洩候補）
resource "aws_athena_named_query" "large_data_transfer" {
  name      = "${var.project_name}-large-data-transfer"
  workgroup = aws_athena_workgroup.flowlogs.id
  database  = aws_glue_catalog_database.flowlogs.name

  query = <<-SQL
    -- 本日の大量データ転送フロー（上位 50 件）。
    -- bytes が異常に大きい ACCEPT フローはデータ漏洩の可能性を示す。
    -- 特にプライベートサブネットから外部 IP への大量転送を重点的に確認する。
    SELECT
      srcaddr,
      dstaddr,
      dstport,
      protocol,
      sum(bytes)   AS total_bytes,
      sum(packets) AS total_packets,
      count(*)     AS flow_count,
      vpc_id,
      subnet_id
    FROM "${aws_glue_catalog_database.flowlogs.name}"."vpc_flow_logs"
    WHERE
      action = 'ACCEPT'
      AND year  = year(current_date)
      AND month = month(current_date)
      AND day   = day(current_date)
    GROUP BY srcaddr, dstaddr, dstport, protocol, vpc_id, subnet_id
    ORDER BY total_bytes DESC
    LIMIT 50;
  SQL
}
