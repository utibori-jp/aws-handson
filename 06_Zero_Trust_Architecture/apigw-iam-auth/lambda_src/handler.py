"""
Lambda handler for IAM-authenticated API Gateway endpoint.

SCS 的観点:
  - requestContext.identity.userArn を返すことで、どの IAM エンティティが
    SigV4 署名を行ったかをレスポンスで確認できる。
  - 本番では呼び出し元の ARN を使ってさらなる認可ロジックを実装できる。
"""
import json


def handler(event, context):
    # SigV4 署名付きリクエストの場合、requestContext.identity に呼び出し元の情報が含まれる。
    caller_arn = (
        event.get("requestContext", {})
        .get("identity", {})
        .get("userArn", "unknown")
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Hello from IAM-authenticated API",
            "caller": caller_arn,
        }),
    }
