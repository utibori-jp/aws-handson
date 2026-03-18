# =============================================================================
# ecs.tf — ecs-fargate-security
# ECS クラスター + タスク定義（コンテナセキュリティ設定）+ サービスの定義。
#
# 【readonlyRootFilesystem とは】
# コンテナのルートファイルシステムを読み取り専用にする設定。
# 攻撃者がコンテナに侵入した際に、実行ファイルやスクリプトをディスクに書き込めなくなる。
# 永続的なマルウェアのドロップやバイナリの改ざんを防ぐ。SCS頻出コンテナセキュリティ設定。
#
# 【noNewPrivileges とは】
# コンテナ内のプロセスが setuid/setgid ビット等を使って権限を昇格することを防ぐ。
# Linux カーネルの no_new_privs フラグに対応する。
#
# 【tmpfs マウントとは】
# readonlyRootFilesystem = true にすると /tmp への書き込みもできなくなるが、
# アプリによっては一時ファイルが必要なケースがある。
# tmpfs（メモリ上の一時ファイルシステム）をマウントすることで対処する。
# メモリ上にのみ存在するため、コンテナ停止と同時に消える（永続化されない）。
#
# 【確認ポイント（apply 後）】
# 1. ECS コンソールでタスク定義の「コンテナ定義」を開き、
#    「読み取り専用ルートファイルシステム」が有効になっていることを確認する
# 2. タスクロールに「最小権限ポリシー」のみがアタッチされていることを確認する
# 3. 実行ロールと タスクロールが分離されていることをコンソールで確認する
# =============================================================================

# ---
# CloudWatch Logs ロググループ
# ---

# ECS タスクのログ出力先。
# タスク定義の logConfiguration で参照する。
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-ecs-logs"
  }
}

# ---
# ECS クラスター
# ---

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  # Container Insights を有効化してコンテナのメトリクス・ログを収集する。
  # 有効化によりコストが発生するが、監視・セキュリティ調査に有用なため有効にする。
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# ---
# ECS タスク定義
# ---

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  # Fargate の最小スペック。ハンズオン用途で十分。
  cpu    = 256
  memory = 512

  # 実行ロールとタスクロールをそれぞれ分離して設定する。
  # 実行ロール: ECS 自体が使う（ECR Pull, CloudWatch Logs 書き込み）
  # タスクロール: コンテナ内アプリが使う（S3 GetObject など）
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "app"
      # パブリック ECR の nginx イメージを使用。ECR リポジトリの作成コストを省く。
      image = "public.ecr.aws/nginx/nginx:latest"

      # 【コンテナセキュリティ設定 1】
      # ルートファイルシステムを読み取り専用にする。
      # これにより攻撃者がコンテナ内にファイルを書き込むことができなくなる。
      readonlyRootFilesystem = true

      # 【コンテナセキュリティ設定 2】
      # 新しい権限の取得を禁止する（setuid/setgid ビットによる権限昇格防止）。
      linuxParameters = {
        initProcessEnabled = true
        tmpfs = [
          {
            # readonlyRootFilesystem = true でも /tmp への書き込みが必要な場合のための設定。
            # tmpfs はメモリ上に存在するため、コンテナ停止で消える（永続化されない）。
            containerPath = "/tmp"
            size          = 64
          }
        ]
      }

      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      # CloudWatch Logs へのログ出力設定。
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-task"
  }
}

# ---
# ECS サービス
# ---

resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.ecs_task.id]

    # プライベートサブネットに配置するため、パブリック IP は不要。
    # NAT Gateway がない場合は ECR Pull のために VPC Endpoint が必要になる（追加課題）。
    assign_public_ip = false
  }

  tags = {
    Name = "${var.project_name}-service"
  }
}
