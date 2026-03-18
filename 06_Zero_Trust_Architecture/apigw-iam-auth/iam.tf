# =============================================================================
# iam.tf
# Lambda 実行ロール。CloudWatch Logs への書き込み権限のみ付与する。
# SCS 的観点: Lambda に必要以上の権限を与えないことが最小権限原則の実践。
# =============================================================================

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-apigw-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-apigw-lambda-role"
  }
}

# AWSLambdaBasicExecutionRole: CloudWatch Logs への書き込み権限のみを含む最小ポリシー。
# Lambda が VPC 外にある場合はこれだけで十分。
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
