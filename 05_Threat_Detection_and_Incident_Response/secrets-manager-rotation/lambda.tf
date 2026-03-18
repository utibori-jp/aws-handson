# =============================================================================
# lambda.tf — secrets-manager-rotation
# ローテーター Lambda の定義。archive_file でビルドレスデプロイ。
# =============================================================================

data "archive_file" "rotate_secret" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/rotate_secret.py"
  output_path = "${path.module}/lambda_src/rotate_secret.zip"
}

resource "aws_cloudwatch_log_group" "rotate_secret" {
  name              = "/aws/lambda/${var.project_name}-rotate-secret"
  retention_in_days = 30

  tags = {
    Name = "/aws/lambda/${var.project_name}-rotate-secret"
  }
}

resource "aws_lambda_function" "rotate_secret" {
  function_name    = "${var.project_name}-rotate-secret"
  role             = aws_iam_role.rotation_lambda.arn
  handler          = "rotate_secret.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.rotate_secret.output_path
  source_code_hash = data.archive_file.rotate_secret.output_base64sha256

  # ローテーションの各フェーズは数秒以内に完了する想定。
  timeout = 30

  depends_on = [aws_cloudwatch_log_group.rotate_secret]

  tags = {
    Name = "${var.project_name}-rotate-secret"
  }
}

# Secrets Manager がこの Lambda を呼び出すための許可。
# ローテーション設定（secrets.tf）より先にこのリソースが存在する必要がある。
resource "aws_lambda_permission" "allow_secretsmanager" {
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_secret.function_name
  principal     = "secretsmanager.amazonaws.com"
  # source_arn でシークレット ARN を指定すると Confused Deputy 攻撃を防げる。
  # ただしシークレット ARN と Lambda のデプロイが同時で循環参照になるため、
  # ハンズオンでは source_account のみで制限する（十分な保護）。
  source_account = local.account_id
}
