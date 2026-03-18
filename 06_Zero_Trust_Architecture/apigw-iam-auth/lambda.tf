# =============================================================================
# lambda.tf
# Lambda 関数本体と CloudWatch Logs グループ。
# archive プロバイダで handler.py を ZIP 化してデプロイする。
# =============================================================================

# handler.py を ZIP に固める。ファイルが変わると source_content_hash が変わり
# Lambda が自動的に再デプロイされる。
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/handler.py"
  output_path = "${path.module}/lambda_src/handler.zip"
}

# ロググループを先に作成することで保持期間を管理できる。
# Lambda が自動生成したグループは保持期間が無期限になるため要注意。
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-apigw-handler"
  retention_in_days = 7 # ハンズオン環境: コスト削減のため短期間に設定

  tags = {
    Name = "${var.project_name}-apigw-handler-logs"
  }
}

resource "aws_lambda_function" "main" {
  function_name    = "${var.project_name}-apigw-handler"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  # ログは上で作成したロググループに書き込まれる。
  logging_config {
    log_group  = aws_cloudwatch_log_group.lambda.name
    log_format = "Text"
  }

  tags = {
    Name = "${var.project_name}-apigw-handler"
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# API Gateway が Lambda を呼び出せるよう許可する。
# source_arn を限定してこの API からの呼び出しのみ許可する（最小権限）。
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"
  # source_arn: 特定の API の特定のメソッドからのみ呼び出しを許可する。
  source_arn = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
