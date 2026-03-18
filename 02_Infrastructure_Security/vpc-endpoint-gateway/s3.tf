# =============================================================================
# s3.tf — vpc-endpoint-gateway
# エンドポイント経由アクセスの検証用 S3 バケット。
#
# EC2 インスタンス（プライベートサブネット）から、
# NAT Gateway を経由せずにこのバケットにアクセスできることを確認するための検証用。
#
# 【演習手順（apply 後）】
# 1. プライベートサブネットの EC2 インスタンスから以下を実行する：
#      aws s3 ls s3://<bucket_name> --region ap-northeast-1
#    → VPC Endpoint 経由でアクセスできることを確認する
# 2. VPC Flow Logs（00_Baseline の CloudTrail）でトラフィックを確認する
# 3. エンドポイントポリシーから DenyOtherAccountS3 を一時的に削除し、
#    他アカウントのバケットにアクセスできてしまうことを確認した後、元に戻す
# =============================================================================

resource "aws_s3_bucket" "endpoint_test" {
  bucket        = "${var.project_name}-endpoint-test"
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-endpoint-test"
    Purpose = "VPCEndpoint-Demo"
  }
}

# パブリックアクセスを全面ブロック。
# このバケットは VPC Endpoint 経由（+ IAM 認証）でのみアクセスする想定。
resource "aws_s3_bucket_public_access_block" "endpoint_test" {
  bucket = aws_s3_bucket.endpoint_test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "endpoint_test" {
  bucket = aws_s3_bucket.endpoint_test.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
