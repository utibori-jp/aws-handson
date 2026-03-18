# =============================================================================
# lambda.tf — eventbridge-lambda-remediation
# Lambda 関数定義。archive_file でソースを zip 化して直接デプロイする。
# 外部ビルドツール不要で terraform apply のみで完結する。
# =============================================================================

# ---
# KMS 削除キャンセル Lambda
# ---

data "archive_file" "cancel_kms_deletion" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/cancel_kms_deletion.py"
  output_path = "${path.module}/lambda_src/cancel_kms_deletion.zip"
}

resource "aws_cloudwatch_log_group" "cancel_kms_deletion" {
  name              = "/aws/lambda/${var.project_name}-cancel-kms-deletion"
  retention_in_days = 30

  tags = {
    Name = "/aws/lambda/${var.project_name}-cancel-kms-deletion"
  }
}

resource "aws_lambda_function" "cancel_kms_deletion" {
  function_name    = "${var.project_name}-cancel-kms-deletion"
  role             = aws_iam_role.cancel_kms_deletion.arn
  handler          = "cancel_kms_deletion.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.cancel_kms_deletion.output_path
  source_code_hash = data.archive_file.cancel_kms_deletion.output_base64sha256

  # KMS API 呼び出しは通常数秒で完了するため 30 秒で十分。
  timeout = 30

  depends_on = [aws_cloudwatch_log_group.cancel_kms_deletion]

  tags = {
    Name = "${var.project_name}-cancel-kms-deletion"
  }
}

# EventBridge が Lambda を呼び出すための許可。
resource "aws_lambda_permission" "allow_eventbridge_kms" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cancel_kms_deletion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.kms_key_deletion.arn
}

# ---
# SG ルール取り消し Lambda
# ---

data "archive_file" "revoke_sg_ingress" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/revoke_sg_ingress.py"
  output_path = "${path.module}/lambda_src/revoke_sg_ingress.zip"
}

resource "aws_cloudwatch_log_group" "revoke_sg_ingress" {
  name              = "/aws/lambda/${var.project_name}-revoke-sg-ingress"
  retention_in_days = 30

  tags = {
    Name = "/aws/lambda/${var.project_name}-revoke-sg-ingress"
  }
}

resource "aws_lambda_function" "revoke_sg_ingress" {
  function_name    = "${var.project_name}-revoke-sg-ingress"
  role             = aws_iam_role.revoke_sg_ingress.arn
  handler          = "revoke_sg_ingress.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.revoke_sg_ingress.output_path
  source_code_hash = data.archive_file.revoke_sg_ingress.output_base64sha256

  timeout = 30

  depends_on = [aws_cloudwatch_log_group.revoke_sg_ingress]

  tags = {
    Name = "${var.project_name}-revoke-sg-ingress"
  }
}

resource "aws_lambda_permission" "allow_eventbridge_sg" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.revoke_sg_ingress.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sg_ingress_all_open.arn
}
