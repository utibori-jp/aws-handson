# =============================================================================
# s3.tf — vpc-endpoint-gateway
# エンドポイント経由アクセスの検証用 S3 バケット。
#
# EC2 インスタンス（プライベートサブネット）から、
# NAT Gateway を経由せずにこのバケットにアクセスできることを確認するための検証用。
#
# 【確認ポイント】
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

# デフォルト暗号化を有効化する。
# SCS的観点：KMS（SSE-KMS）を使うとキーポリシーでアクセス制御できるが、
# 演習用バケットのため AES256（SSE-S3）で十分。
resource "aws_s3_bucket_server_side_encryption_configuration" "endpoint_test" {
  bucket = aws_s3_bucket.endpoint_test.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---
# peer アカウントの S3 バケット（エンドポイントポリシー Deny の証明用）
# ---
# このバケットは「エンドポイントポリシーが確かに Deny しているか」を確認するためのもの。
# バケットポリシーで learner EC2 ロールの ListBucket を明示的に許可しておくことで、
# アクセス拒否の原因が「S3 バケットポリシー」ではなく「エンドポイントポリシー」であると特定できる。
resource "aws_s3_bucket" "peer_endpoint_test" {
  provider      = aws.peer
  bucket        = "${var.project_name}-peer-endpoint-test"
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-peer-endpoint-test"
    Purpose = "VPCEndpoint-CrossAccount-Demo"
  }
}

resource "aws_s3_bucket_public_access_block" "peer_endpoint_test" {
  provider = aws.peer
  bucket   = aws_s3_bucket.peer_endpoint_test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# learner アカウントの EC2 ロールに ListBucket を許可するバケットポリシー。
# これにより「エンドポイントポリシーさえなければアクセスできる」状態を作る。
resource "aws_s3_bucket_policy" "peer_endpoint_test" {
  provider = aws.peer
  bucket   = aws_s3_bucket.peer_endpoint_test.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowLearnerEC2Role"
      Effect = "Allow"
      Principal = {
        AWS = "arn:${local.partition}:iam::${var.learner_account_id}:role/${var.project_name}-ec2-ssm-role"
      }
      Action   = "s3:ListBucket"
      Resource = aws_s3_bucket.peer_endpoint_test.arn
    }]
  })
}
