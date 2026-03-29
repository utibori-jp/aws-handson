# =============================================================================
# organizations.tf — learner アカウント + IAM Identity Center
#
# Learner メンバーアカウントを Organizations で払い出し、
# IAM Identity Center の PermissionSet（Admin / ReadOnly）を割り当てる。
#
# 【使い方】
# - マネコン確認: IAM Identity Center のアクセスポータルから
#   Admin（リソース操作）か ReadOnly（参照のみ）を選んでサインイン
# - CLI確認: aws configure sso で learner-admin / learner-readonly プロファイルを設定後、
#   各コマンドに --profile learner-admin などを指定する
# =============================================================================

# IAM Identity Center のインスタンス情報を取得する。
# SSO 管理はインスタンス ARN と Identity Store ID を起点に行う。
data "aws_ssoadmin_instances" "main" {}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
}

# PermissionSet を割り当てる Identity Center ユーザーをユーザー名で引く。
# var.sso_username には Identity Center コンソール「ユーザー」画面に表示される UserName を指定する。
# UserName は Identity Center 固有の属性で、メールアドレスとは限らない。
data "aws_identitystore_user" "main" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.sso_username
    }
  }
}

# ---
# Learner メンバーアカウント
# ---

resource "aws_organizations_account" "learner" {
  name  = "${var.project_name}-learner"
  email = var.learner_account_email

  # close_on_deletion = true にすることで、terraform destroy 時にアカウントを閉鎖する。
  # ハンズオン環境では destroy を気軽に実行したいため有効にしている。
  # 本番環境では false にして誤削除を防ぐことを推奨する。
  close_on_deletion = true

  tags = {
    Name = "${var.project_name}-learner"
  }
}

# ---
# Permission Sets
# ---

# 管理者権限セット。
# リソースの作成・変更など、ハンズオンで実際に操作を試す際に使用する。
resource "aws_ssoadmin_permission_set" "learner_admin" {
  name             = "${var.project_name}-learner-admin"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
  description      = "Admin access to learner account for hands-on verification"
}

resource "aws_ssoadmin_managed_policy_attachment" "learner_admin" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.learner_admin.arn
}

# 読み取り専用権限セット。
# ポリシー内容の確認やリソースの状態確認など、変更を伴わない検証に使用する。
resource "aws_ssoadmin_permission_set" "learner_readonly" {
  name             = "${var.project_name}-learner-readonly"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
  description      = "ReadOnly access to learner account for hands-on observation"
}

resource "aws_ssoadmin_managed_policy_attachment" "learner_readonly" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.learner_readonly.arn
}

# ---
# Peer メンバーアカウント
# ---

# クロスアカウントアクセスや複数アカウント検証に使用する汎用メンバーアカウント。
# cross-account-role での AssumeRole 先として使用するほか、
# 複数アカウントが必要な検証（Security Hub 集約等）にも利用できる。
resource "aws_organizations_account" "peer" {
  name  = "${var.project_name}-peer"
  email = var.peer_account_email

  close_on_deletion = true

  tags = {
    Name = "${var.project_name}-peer"
  }
}

# learner と同じ Permission Set を peer アカウントにも割り当てる。
# Identity Center ユーザーが peer アカウントへ Admin / ReadOnly でサインインできるようにする。
resource "aws_ssoadmin_account_assignment" "peer_admin" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.learner_admin.arn
  principal_id       = data.aws_identitystore_user.main.user_id
  principal_type     = "USER"
  target_id          = aws_organizations_account.peer.id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "peer_readonly" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.learner_readonly.arn
  principal_id       = data.aws_identitystore_user.main.user_id
  principal_type     = "USER"
  target_id          = aws_organizations_account.peer.id
  target_type        = "AWS_ACCOUNT"
}

# ---
# Account Assignments — learner アカウントへの割り当て
# ---

resource "aws_ssoadmin_account_assignment" "learner_admin" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.learner_admin.arn
  principal_id       = data.aws_identitystore_user.main.user_id
  principal_type     = "USER"
  target_id          = aws_organizations_account.learner.id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "learner_readonly" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.learner_readonly.arn
  principal_id       = data.aws_identitystore_user.main.user_id
  principal_type     = "USER"
  target_id          = aws_organizations_account.learner.id
  target_type        = "AWS_ACCOUNT"
}
