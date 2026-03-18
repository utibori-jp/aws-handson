# =============================================================================
# apigw.tf
# REST API + AWS_IAM 認証 + Lambda プロキシ統合。
#
# Zero Trust 的観点:
#   - authorization = "AWS_IAM" により、全リクエストに SigV4 署名が必要になる。
#   - 署名なしのリクエストは API Gateway レベルで 403 を返す（Lambda まで到達しない）。
#   - 呼び出し側は execute-api:Invoke 権限を持つ IAM エンティティである必要がある。
# =============================================================================

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-iam-auth-api"
  description = "REST API with AWS_IAM authentication for Zero Trust hands-on"

  # REGIONAL: デプロイリージョン内のクライアントを対象とする。
  # EDGE: CloudFront 経由でグローバル配信。ハンズオンでは REGIONAL で十分。
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project_name}-iam-auth-api"
  }
}

# /hello リソースを作成する。
resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "hello"
}

# GET /hello メソッド。authorization = "AWS_IAM" が Zero Trust の肝。
# SigV4 署名がないリクエストは API Gateway が自動的に 403 を返す。
resource "aws_api_gateway_method" "hello_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

# Lambda プロキシ統合: event オブジェクト全体を Lambda に渡す。
# HTTP_PROXY と異なり、Lambda がレスポンス全体を制御できる。
resource "aws_api_gateway_integration" "hello_get" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.hello_get.http_method
  integration_http_method = "POST" # Lambda 統合は常に POST
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.main.invoke_arn
}

# デプロイメント: メソッドや統合の変更を反映するために必要。
# triggers を使って設定変更時に自動再デプロイする。
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello.id,
      aws_api_gateway_method.hello_get.id,
      aws_api_gateway_integration.hello_get.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ステージ: デプロイメントの公開エンドポイント。URL に "v1" が含まれる。
resource "aws_api_gateway_stage" "v1" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = "v1"

  # アクセスログをここで設定することも可能だが、ハンズオンでは省略する。
  # 本番では CloudWatch Logs への X-Ray トレースと合わせて有効化すること。

  tags = {
    Name = "${var.project_name}-apigw-stage-v1"
  }
}
