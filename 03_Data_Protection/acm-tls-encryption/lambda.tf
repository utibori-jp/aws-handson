# =============================================================================
# lambda.tf — acm-tls-encryption
# ALB のバックエンドとなる最小構成の Lambda 関数。
# HTTPS アクセスの成功を確認するための 200 レスポンスを返す。
#
# 【Lambda を ALB ターゲットにする仕組み】
# ALB は aws_lb_target_group（target_type = "lambda"）を通じて Lambda を呼び出す。
# Lambda には aws_lambda_permission で ALB からの呼び出しを許可する。
# ALB は HTTP リクエストをイベントオブジェクトに変換して Lambda に渡し、
# Lambda のレスポンス（ALB 互換形式）を HTTP レスポンスに変換してクライアントへ返す。
#
# 【ALB 互換レスポンス形式】
# Lambda が ALB に返すレスポンスは以下の形式である必要がある。
# 不正な形式の場合 ALB は 502 Bad Gateway を返す。
#   {
#     "statusCode": 200,
#     "statusDescription": "200 OK",
#     "isBase64Encoded": false,
#     "headers": {"Content-Type": "text/plain"},
#     "body": "..."
#   }
#
# 【archive_file でインライン zip を使う理由】
# 外部ファイル（src/handler.py）を置かずに Terraform コードのみでモジュールを自包できる。
# apply 時に lambda_handler.zip が自動生成される（.gitignore に追加推奨）。
#
# 【確認ポイント】
# Lambda を直接テスト（ALB を経由せず）：
# aws lambda invoke \
#   --function-name "$(terraform output -raw lambda_function_name)" \
#   --payload '{"httpMethod":"GET","path":"/","headers":{}}' \
#   --cli-binary-format raw-in-base64-out \
#   /tmp/lambda_response.json && cat /tmp/lambda_response.json
# → {"statusCode": 200, "body": "Hello, HTTPS World! [GET /]"}
# =============================================================================

# Lambda 実行ロール。
# AWSLambdaBasicExecutionRole で CloudWatch Logs への書き込みのみを許可する（最小権限）。
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-lambda-exec"
  }
}

# CloudWatch Logs への書き込みのみ許可する。
# ALB のバックエンドとして機能するだけなので、他の AWS サービスへのアクセスは不要。
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# インライン Python コードを zip 化する。
# output_path に生成される lambda_handler.zip は .gitignore への追加を推奨。
data "archive_file" "lambda_handler" {
  type        = "zip"
  output_path = "${path.module}/lambda_handler.zip"

  source {
    content  = <<-PYTHON
      def handler(event, context):
          """
          ALB からのリクエストを受け取り 200 レスポンスを返す。
          ALB 互換形式（statusCode, statusDescription, isBase64Encoded, headers, body）が必要。
          """
          path   = event.get("path", "/")
          method = event.get("httpMethod", "GET")
          return {
              "statusCode": 200,
              "statusDescription": "200 OK",
              "isBase64Encoded": False,
              "headers": {"Content-Type": "text/plain"},
              "body": f"Hello, HTTPS World! [{method} {path}]",
          }
    PYTHON
    filename = "handler.py"
  }
}

resource "aws_lambda_function" "backend" {
  function_name = "${var.project_name}-tls-backend"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "handler.handler"

  filename = data.archive_file.lambda_handler.output_path
  # 作成するZipファイルは、中身が書き換わってもファイル名自体は変わらない。
  # ハッシュ値を比較することで、コードが変わっていない場合はZipファイルのアップロードを省略できる。
  source_code_hash = data.archive_file.lambda_handler.output_base64sha256

  tags = {
    Name = "${var.project_name}-tls-backend"
  }
}

# ALB からの Lambda 呼び出しを許可するリソースベースポリシー。
# source_arn でターゲットグループ ARN を指定することで、
# 「この ALB ターゲットグループからのみ」に呼び出しを限定する（最小権限）。
resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}

# ALB → Lambda のターゲットグループ。
# target_type = "lambda" の場合、VPC・ポート・プロトコルの設定は不要。
resource "aws_lb_target_group" "lambda" {
  name        = "${var.project_name}-lambda-tg"
  target_type = "lambda"

  tags = {
    Name = "${var.project_name}-lambda-tg"
  }
}

# Lambda 関数をターゲットグループに登録する。
# aws_lambda_permission が先に作成されていないと ALB が Lambda を呼び出せないため
# depends_on で順序を明示する。
resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.backend.arn
  depends_on       = [aws_lambda_permission.alb]
}
