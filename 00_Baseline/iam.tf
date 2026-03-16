# =============================================================================
# iam.tf — iam-base
# マネジメントコンソールからリソースを「見る」ための学習用IAMユーザーを作成する。
# Terraformの実行はAWS SSOプロファイル（terraform-sso）で直接行うため、
# 別途Terraform実行用ロールは用意しない。
# =============================================================================

# 学習用ユーザーをまとめるグループ。
# ユーザー個別ではなくグループにポリシーを付与することで、
# 複数ユーザーへの権限管理が容易になる（IAMベストプラクティス）。
resource "aws_iam_group" "learners" {
  name = "${var.project_name}-learners"
}

# ベースラインはReadOnlyAccess。
# 各章のハンズオンで必要な追加権限はそれぞれの章で付与する。
# 01章では、このユーザーへの権限境界（Permissions Boundary）設定を検証する。
resource "aws_iam_group_policy_attachment" "learners_readonly" {
  group      = aws_iam_group.learners.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 学習用IAMユーザー。
# force_destroy = true により、アクセスキーやMFAデバイスが残っていてもdestroyできる。
resource "aws_iam_user" "learner" {
  name          = "${var.project_name}-learner"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-learner"
  }
}

resource "aws_iam_user_group_membership" "learner" {
  user   = aws_iam_user.learner.name
  groups = [aws_iam_group.learners.name]
}
