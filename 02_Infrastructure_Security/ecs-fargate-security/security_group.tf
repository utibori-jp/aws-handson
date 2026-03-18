# =============================================================================
# security_group.tf — ecs-fargate-security
# ECS Fargate タスク用のセキュリティグループ。
#
# 【設計方針】
# - inbound: 全拒否（このモジュールでは ALB なし、外部からの直接アクセス不要）
# - outbound: HTTPS（443）のみ許可
#   → ECR からのイメージ Pull・CloudWatch Logs への書き込みは HTTPS を使用
#   → S3 へのアクセスも HTTPS (443)。VPC Endpoint 経由なら S3 プレフィックスリストを使うことも可
#
# 【SCS的観点】
# 最小権限はネットワークレベルにも適用する。
# 不要なポートを開放しないことで、侵害された際の横移動（lateral movement）を防ぐ。
# =============================================================================

resource "aws_security_group" "ecs_task" {
  name        = "${var.project_name}-ecs-task"
  description = "Security group for ECS Fargate tasks — deny all inbound, allow HTTPS outbound only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-ecs-task"
  }
}

# inbound: 全拒否（ルールなし = デフォルト拒否）。
# ALB がある場合は ALB の SG からの inbound のみを許可するルールを追加する。

# outbound: HTTPS のみ許可。
# ECR イメージ Pull・CloudWatch Logs 書き込み・S3 アクセスに必要。
resource "aws_vpc_security_group_egress_rule" "ecs_task_https_out" {
  security_group_id = aws_security_group.ecs_task.id

  description = "Allow HTTPS outbound for ECR pull, CloudWatch Logs, and S3 access"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}
