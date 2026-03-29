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
# 【確認ポイント】
# ── 事前準備（初回のみ）──
# Session Manager Plugin をインストールする。ECS Exec は SSM セッションを使うため必須。
#   https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
#
# ── ECS Exec でコンテナ内から動作確認 ──
# 1. コンテナに接続する
#    （クラスター名は terraform output ecs_cluster_name で確認）
#    （タスク ID は ECS サービスが動的に管理するため terraform output には出せない。
#      aws ecs list-tasks --cluster <cluster-name> --profile learner-admin で確認する）
#    aws ecs execute-command \
#      --cluster <cluster-name> \
#      --task <task-id> \
#      --container app \
#      --interactive \
#      --command "bash" \
#      --profile learner-admin
#
# 2. コンテナ内で以下を実行して readonlyRootFilesystem を確認する
#    touch /usr/local/bin/test   # → touch: /usr/local/bin/test: Read-only file system  ← 書き込み拒否
#    touch /tmp/test.txt         # → 成功（tmpfs は書き込み可）
#
# ── タスクロール最小権限の確認 ──
# 3. コンテナ内で AWS CLI を使ってタスクロールの権限を確認する
#    （コンテナ内の AWS CLI はプロファイル不要。タスクロールの認証情報が自動で使われる）
#    aws s3 ls                                                    # → 成功（s3:ListAllMyBuckets が許可）
#    aws s3 mb s3://scs-handson-dummy-$(date +%s)     # → AccessDenied（s3:CreateBucket は未付与）
# =============================================================================

# ---
# CloudWatch Logs ロググループ
# ---

# ECS タスクのログ出力先。
# タスク定義の logConfiguration で参照する。
resource "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.project_name}"
  # Fargate タスクのログ出力先として必要な設定。
  # タスク定義の logConfiguration で参照する。
  # このモジュールのセキュリティ検証には直接使わないが、
  # nginx の起動ログ程度であれば以下で確認できる。
  #   aws logs tail /ecs/scs-handson --follow
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

  # 本番・実務では Container Insights を有効化してコンテナのメトリクス・ログを収集するのが推奨。
  # SCS的観点でも異常検知・セキュリティ調査に有用なため有効化が基本。
  # このモジュールでは確認ポイントで使用しないため、コスト節約のため無効にしている。
  setting {
    name  = "containerInsights"
    value = "disabled"
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
  # タスクロール: コンテナ内アプリが使う（S3 ListAllMyBuckets の検証など）
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name = "app"
      # パブリック ECR の aws-cli イメージを使用。ECR リポジトリの作成コストを省く。
      # タスクロールの最小権限を AWS CLI で直接検証するためにこのイメージを選択している。
      image = "public.ecr.aws/aws-cli/aws-cli:latest"

      # aws-cli イメージのデフォルトエントリポイントは aws コマンド実行後に終了するため、
      # tail -f /dev/null でプロセスを常駐させ ECS Exec で接続できる状態を維持する。
      entryPoint = ["tail", "-f", "/dev/null"]

      # 【コンテナセキュリティ設定 1】
      # ルートファイルシステムを読み取り専用にする。
      # これにより攻撃者がコンテナ内にファイルを書き込むことができなくなる。
      readonlyRootFilesystem = true

      # 【コンテナセキュリティ設定 2】
      # noNewPrivileges: コンテナ内プロセスが setuid/setgid バイナリで権限昇格することを防ぐ。
      # これがない場合、コンテナが侵害されると以下のリスクがある：
      # - イメージ内の setuid root バイナリ（su 等）を使って root に昇格できる
      # - root 昇格後にコンテナブレイクアウト（ホスト侵害）を試みられる
      # - 最小権限で起動したプロセスが権限昇格し、機密データへのアクセスが可能になる
      linuxParameters = {
        noNewPrivileges    = true
        initProcessEnabled = true
        tmpfs = [
          {
            # readonlyRootFilesystem = true でも /tmp への書き込みが必要な場合のための設定。
            # tmpfs はメモリ上に存在するため、コンテナ停止で消える（永続化されない）。
            containerPath = "/tmp"
            size          = 64
          },
          # --- ECS Exec（SSM Session Manager）に必要な書き込み領域 ---
          {
            # SSM エージェントが状態ファイルを書き込むディレクトリ。
            # ECS Exec は initProcessEnabled = true で起動した SSM エージェント経由で動作するため、
            # readonlyRootFilesystem 環境でもこのパスへの書き込みが必要。
            containerPath = "/var/lib/amazon/ssm"
            size          = 64
          },
          {
            # SSM エージェントのログ出力先。
            containerPath = "/var/log/amazon/ssm"
            size          = 64
          }
        ]
      }

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

  # ECS Exec を有効化する。タスクロールに SSM Messages 権限が必要（iam.tf 参照）。
  # コンテナに exec して readonlyRootFilesystem などのセキュリティ設定を直接検証できる。
  enable_execute_command = true

  network_configuration {
    subnets         = [aws_subnet.public.id]
    security_groups = [aws_security_group.ecs_task.id]

    # NAT Gateway なし構成のため、public IP を付与してインターネット経由で
    # ECR Pull・CloudWatch Logs へのアウトバウンドを行う。
    # inbound SG ルールはなし（全拒否）のため、外部からコンテナへのアクセスは不可。
    assign_public_ip = true
  }

  tags = {
    Name = "${var.project_name}-service"
  }
}
