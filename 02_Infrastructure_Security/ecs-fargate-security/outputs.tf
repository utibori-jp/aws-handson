# =============================================================================
# outputs.tf
# apply 後に確認したいリソース情報を出力する。
# =============================================================================

# ---
# ECS
# ---

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.main.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

# ---
# IAM
# ---

output "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role (used by ECS to pull images and write logs)"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role (used by the application container)"
  value       = aws_iam_role.ecs_task.arn
}

# ---
# ネットワーク
# ---

output "ecs_task_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_task.id
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Logs log group name for ECS tasks"
  value       = aws_cloudwatch_log_group.ecs.name
}
