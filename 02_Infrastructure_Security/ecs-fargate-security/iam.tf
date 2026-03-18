# =============================================================================
# iam.tf — ecs-fargate-security
# ECS Fargate の「実行ロール」と「タスクロール」を分離して定義する。
#
# 【実行ロール（Task Execution Role）とは】
# ECS がコンテナを起動するために使う権限。
# ECR からイメージを Pull する・CloudWatch Logs にログを書き込む、
# Secrets Manager からシークレットを取得するなど「ECS 自体が必要な権限」。
# タスク（アプリ）は実行ロールの権限を直接使えない。
#
# 【タスクロール（Task Role）とは】
# コンテナ内で動くアプリが AWS API を呼ぶための権限。
# EC2 のインスタンスプロファイルに相当する。
# 「アプリが何をしてよいか」を最小権限で定義する。SCS頻出。
#
# 【2つのロールを分離する意義】
# - 実行ロールは ECS が制御するため、アプリが実行ロールの権限を使えない
# - タスクロールはアプリの要件に応じて最小権限で設計できる
# - それぞれ独立して更新・監査できる
# =============================================================================

# ---
# 実行ロール（Task Execution Role）
# ---

data "aws_iam_policy_document" "ecs_execution_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project_name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_execution_assume_role.json

  tags = {
    Name = "${var.project_name}-ecs-execution"
  }
}

# ECS タスク実行に必要な AWS マネージドポリシーをアタッチする。
# ECR からのイメージ Pull・CloudWatch Logs への書き込みが含まれる。
resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---
# タスクロール（Task Role）— アプリが使う権限
# ---

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Name = "${var.project_name}-ecs-task"
  }
}

# タスクロールには「アプリが実際に使う権限だけ」を付与する。
# ここでは学習用として S3 GetObject のみを許可する最小権限ポリシーを定義する。
# 実際のアプリに応じて必要な権限のみを追加すること。
resource "aws_iam_policy" "ecs_task_minimal" {
  name        = "${var.project_name}-ecs-task-minimal"
  description = "Minimal permissions for ECS task — only what the application actually needs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # アプリが S3 バケットからコンテンツを読み取る想定の最小権限。
        # 本番では Resource に特定バケット ARN を指定すること（ワイルドカード禁止）。
        Sid      = "AllowS3ReadForApp"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-task-minimal"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_minimal" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task_minimal.arn
}
