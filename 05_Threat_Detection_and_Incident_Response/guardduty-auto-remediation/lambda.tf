# =============================================================================
# lambda.tf — guardduty-auto-remediation
# Lambda 関数定義。archive_file でソースを zip 化して直接デプロイする。
# 外部ビルドツール不要で terraform apply のみで完結する。
# =============================================================================

# ---
# IAM キー無効化 Lambda
# ---

data "archive_file" "remediate_iam_key" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/remediate_iam_key.py"
  output_path = "${path.module}/lambda_src/remediate_iam_key.zip"
}

resource "aws_cloudwatch_log_group" "remediate_iam_key" {
  name              = "/aws/lambda/${var.project_name}-remediate-iam-key"
  retention_in_days = 30

  tags = {
    Name = "/aws/lambda/${var.project_name}-remediate-iam-key"
  }
}

resource "aws_lambda_function" "remediate_iam_key" {
  function_name    = "${var.project_name}-remediate-iam-key"
  role             = aws_iam_role.remediate_iam_key.arn
  handler          = "remediate_iam_key.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.remediate_iam_key.output_path
  source_code_hash = data.archive_file.remediate_iam_key.output_base64sha256

  # タイムアウトは 30 秒。IAM API 呼び出しは通常数秒で完了する。
  timeout = 30

  # CloudWatch Logs グループが先に存在しないと Lambda がデフォルトグループを作ってしまうため依存を宣言。
  depends_on = [aws_cloudwatch_log_group.remediate_iam_key]

  tags = {
    Name = "${var.project_name}-remediate-iam-key"
  }
}

# EventBridge が Lambda を呼び出すための許可。
resource "aws_lambda_permission" "allow_eventbridge_iam" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate_iam_key.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.iam_remediation.arn
}

# ---
# EC2 隔離 Lambda
# ---

data "archive_file" "isolate_ec2" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/isolate_ec2.py"
  output_path = "${path.module}/lambda_src/isolate_ec2.zip"
}

resource "aws_cloudwatch_log_group" "isolate_ec2" {
  name              = "/aws/lambda/${var.project_name}-isolate-ec2"
  retention_in_days = 30

  tags = {
    Name = "/aws/lambda/${var.project_name}-isolate-ec2"
  }
}

resource "aws_lambda_function" "isolate_ec2" {
  function_name    = "${var.project_name}-isolate-ec2"
  role             = aws_iam_role.isolate_ec2.arn
  handler          = "isolate_ec2.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.isolate_ec2.output_path
  source_code_hash = data.archive_file.isolate_ec2.output_base64sha256

  timeout = 60

  depends_on = [aws_cloudwatch_log_group.isolate_ec2]

  tags = {
    Name = "${var.project_name}-isolate-ec2"
  }
}

resource "aws_lambda_permission" "allow_eventbridge_ec2" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.isolate_ec2.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_remediation.arn
}
