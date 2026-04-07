# =============================================================================
# athena.tf — vpc-flowlogs-athena
# Athena によるフローログ分析に必要なリソースを定義する。
#
# 【Athena・Glue・S3 の関係】
# Athena はクエリエンジンのみで、スキーマ管理とデータ保管は別サービスが担う。
#
#   S3（フローログバケット） ◄─ データ読み取り ─┐
#   Glue Data Catalog        ◄─ スキーマ参照  ─── Athena（クエリエンジン）
#   S3（クエリ結果バケット） ◄─ 結果書き出し  ─┘
#   Athena ワークグループ       出力先・スキャン上限などの実行設定を管理
#
# このファイルでは上図の右側（Athena 側）を構成する。
# S3 フローログバケットは flowlogs.tf で定義済み。
#
# 【クエリ結果が S3 に保存される理由】
# Athena は常駐プロセスを持たないサーバーレスエンジンのため、
# 結果をメモリで保持できない。クエリを実行すると結果を一旦 S3 に書き出し、
# そこからクライアント（コンソール・SDK・JDBC）に渡す仕組みになっている。
# A5M2 や DBeaver のように「叩いたらそのまま返ってくる」動作とは異なり、
# クエリ結果バケットは省略不可の必須リソース。
#
# 【Glue Data Catalog とは】
# テーブルのスキーマ（列名・型・S3 パス・パーティション定義）を管理する
# マネージドメタデータストア。Athena はここを参照してどの S3 パスを
# どのスキーマで読み取るかを決定する。データ本体は S3 に置いたまま。
#
# 【Athena による VPC フローログ分析のユースケース】
# - 拒否トラフィック（REJECT）の一覧表示 → 侵害試行・ポートスキャンの把握
# - EC2 からのアウトバウンド通信の確認 → 想定外の外部接続・C2 通信の検知
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
# クエリの出力先と実行制限をまとめて管理する単位。
# チームや用途ごとにワークグループを分けることでコスト配分やアクセス制御ができる。

resource "aws_athena_workgroup" "flowlogs" {
  name          = "${var.project_name}-flowlogs"
  force_destroy = true # 保存済みクエリが残っていても destroy できるようにする

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
# Glue データベース
# ---
# Athena がメタデータを参照する際の名前空間。
# データベース名にハイフンは使えないため、アンダースコアに置換する。

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
    "projection.year.type"    = "integer"
    "projection.year.range"   = "2024,2030"
    "projection.month.type"   = "integer"
    "projection.month.range"  = "1,12"
    "projection.month.digits" = "2"
    "projection.day.type"     = "integer"
    "projection.day.range"    = "1,31"
    "projection.day.digits"   = "2"
    "projection.hour.type"    = "integer"
    "projection.hour.range"   = "0,23"
    "projection.hour.digits"  = "2"
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

    # カスタム log_format の列定義（flowlogs.tf の log_format と順序・型を合わせる）。
    # フィールド名のハイフンは Glue/Athena の列名に使えないためアンダースコアに変換している。
    columns {
      name = "version"       # フローログのバージョン
      type = "int"
    }
    columns {
      name = "account_id"    # フローが発生した AWS アカウント ID
      type = "string"
    }
    columns {
      name = "interface_id"  # トラフィックを記録した ENI の ID
      type = "string"
    }
    columns {
      name = "srcaddr"       # 送信元 IP アドレス
      type = "string"
    }
    columns {
      name = "dstaddr"       # 宛先 IP アドレス
      type = "string"
    }
    columns {
      name = "srcport"       # 送信元ポート番号
      type = "int"
    }
    columns {
      name = "dstport"       # 宛先ポート番号
      type = "int"
    }
    columns {
      name = "protocol"      # IANA プロトコル番号（6=TCP, 17=UDP など）
      type = "bigint"
    }
    columns {
      name = "packets"       # キャプチャ期間中のパケット数
      type = "bigint"
    }
    columns {
      name = "bytes"         # キャプチャ期間中のバイト数
      type = "bigint"
    }
    columns {
      name = "start"         # キャプチャ開始時刻（Unix タイムスタンプ）
      type = "bigint"
    }
    columns {
      name = "end"           # キャプチャ終了時刻（Unix タイムスタンプ）
      type = "bigint"
    }
    columns {
      name = "action"        # SG / NACL による許可(ACCEPT) または拒否(REJECT)
      type = "string"
    }
    columns {
      name = "log_status"    # ログの記録状態（OK / NODATA / SKIPDATA）
      type = "string"
    }
    # 拡張フィールド（VPC・サブネット・AZ 単位での絞り込みに使う）
    columns {
      name = "vpc_id"
      type = "string"
    }
    columns {
      name = "subnet_id"
      type = "string"
    }
    columns {
      name = "instance_id"   # ENI に紐づく EC2 インスタンス ID（なければ "-"）
      type = "string"
    }
    columns {
      name = "tcp_flags"     # TCP フラグのビットマスク（SYN=2, ACK=16 など）
      type = "int"
    }
    columns {
      name = "type"          # トラフィックの種別（IPv4 / IPv6 / EFA）
      type = "string"
    }
    columns {
      name = "pkt_srcaddr"   # NAT されている場合の元の送信元 IP
      type = "string"
    }
    columns {
      name = "pkt_dstaddr"   # NAT されている場合の元の宛先 IP
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
# 検証シナリオに対応するクエリをあらかじめ保存しておき、Athena コンソールから
# すぐに実行できるようにする。SQL は queries/ ディレクトリで管理する。
# 実行前に WHERE 句のプレースホルダ（public_ip / instance_id）を書き換えること。
#
# 【注意】保存済みクエリはワークグループ単位で管理される。
# Athena コンソール右上のワークグループセレクタで
# "<project_name>-flowlogs" に切り替えないと表示されない。
# デフォルトの "primary" ワークグループでは見えない。

# クエリ 1: 外部からの REJECT ログ（nmap/curl による接続試行の確認）
resource "aws_athena_named_query" "rejected_inbound" {
  name      = "${var.project_name}-rejected-inbound"
  workgroup = aws_athena_workgroup.flowlogs.id
  database  = aws_glue_catalog_database.flowlogs.name
  query = templatefile("${path.module}/queries/rejected_inbound.sql", {
    db_name = aws_glue_catalog_database.flowlogs.name
  })
}

# クエリ 2: EC2 からのアウトバウンドトラフィック（SSM Agent・dnf などの自動通信）
resource "aws_athena_named_query" "outbound_from_ec2" {
  name      = "${var.project_name}-outbound-from-ec2"
  workgroup = aws_athena_workgroup.flowlogs.id
  database  = aws_glue_catalog_database.flowlogs.name
  query = templatefile("${path.module}/queries/outbound_from_ec2.sql", {
    db_name = aws_glue_catalog_database.flowlogs.name
  })
}

# クエリ 3: REJECT されたポートの集計（インターネットスキャンの構造把握）
resource "aws_athena_named_query" "rejected_ports_summary" {
  name      = "${var.project_name}-rejected-ports-summary"
  workgroup = aws_athena_workgroup.flowlogs.id
  database  = aws_glue_catalog_database.flowlogs.name
  query = templatefile("${path.module}/queries/rejected_ports_summary.sql", {
    db_name = aws_glue_catalog_database.flowlogs.name
  })
}
