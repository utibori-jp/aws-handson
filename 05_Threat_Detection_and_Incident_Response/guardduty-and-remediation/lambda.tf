# =============================================================================
# lambda.tf — guardduty-and-remediation
# Lambda 関数定義。archive_file でソースを zip 化して直接デプロイする。
# 外部ビルドツール不要で terraform apply のみで完結する。
# =============================================================================

# ---------------------------------------------------------------------------
# 1. KMS 削除キャンセル Lambda（CloudTrail 起点）
# ---------------------------------------------------------------------------

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

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.remediation_alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.cancel_kms_deletion]

  tags = {
    Name = "${var.project_name}-cancel-kms-deletion"
  }
}

resource "aws_lambda_permission" "allow_eventbridge_kms" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cancel_kms_deletion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.kms_key_deletion.arn
}

# ---------------------------------------------------------------------------
# 2. SG ルール取り消し Lambda（CloudTrail 起点）
# ---------------------------------------------------------------------------

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

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.remediation_alerts.arn
    }
  }

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

# ---------------------------------------------------------------------------
# 3. IAM キー無効化 Lambda（GuardDuty 起点）
# ---------------------------------------------------------------------------

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

  timeout = 30

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.remediation_alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.remediate_iam_key]

  tags = {
    Name = "${var.project_name}-remediate-iam-key"
  }
}

resource "aws_lambda_permission" "allow_eventbridge_iam" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate_iam_key.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_iam_finding.arn
}

# ---------------------------------------------------------------------------
# 4. EC2 隔離 Lambda（GuardDuty 起点）
# ---------------------------------------------------------------------------

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

  # EC2 操作（SG 作成・アタッチ）は複数の API 呼び出しになるため 60 秒に設定する。
  timeout = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.remediation_alerts.arn
    }
  }

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
  source_arn    = aws_cloudwatch_event_rule.guardduty_ec2_finding.arn
}
