# =============================================================================
# secrets.tf — secrets-manager-rotation
# シークレットの定義と自動ローテーション設定。
#
# 【Secrets Manager のシークレットバージョン管理】
# - AWSCURRENT  : 現在有効な認証情報
# - AWSPENDING  : ローテーション中の新しい認証情報（finishSecret 完了前）
# - AWSPREVIOUS : 直前の認証情報（フォールバック用に 1 バージョン保持）
#
# ローテーション失敗時に AWSPREVIOUS が残っているため、
# アプリケーションは旧認証情報でサービスへの接続を継続できる（SCS 頻出の可用性設計）。
#
# 【AWS Managed Key との比較】
# デフォルトでは Secrets Manager は AWS Managed Key（aws/secretsmanager）を使う。
# CMK を使うことで:
# - CloudTrail に kms:Decrypt ログが残り「誰がいつシークレットにアクセスしたか」を監査できる
# - キーポリシーで「Secrets Manager 経由のみ復号可能」に制限できる（kms.tf 参照）
# =============================================================================

# ローテーション対象のシークレット。
# JSON 形式で username と password を保持するダミー認証情報。
resource "aws_secretsmanager_secret" "app_credential" {
  name        = "${var.project_name}/app/credential"
  description = "Dummy application credential for rotation handson"

  # CMK で暗号化する（kms.tf の ViaService 条件が適用される）。
  kms_key_id = aws_kms_key.secrets_cmk.arn

  # ハンズオン用として最短の削除待機期間（7 日）。
  # デフォルトは 30 日。この期間内は deleted 状態でも復元可能。
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/app/credential"
  }
}

# 初期バージョン（AWSCURRENT）。
# ローテーション後は AWSPREVIOUS に降格され、新しいパスワードが AWSCURRENT になる。
resource "aws_secretsmanager_secret_version" "initial" {
  secret_id = aws_secretsmanager_secret.app_credential.id

  secret_string = jsonencode({
    username = "app-user"
    password = "initial-password-change-me"
    # 本番環境では host / port / dbname なども含めて格納する。
    # Secrets Manager はこの JSON 全体を暗号化して保存する。
  })
}

# ローテーション設定。
# Lambda 関数を呼び出して自動的にシークレットを更新する。
resource "aws_secretsmanager_secret_rotation" "app" {
  secret_id           = aws_secretsmanager_secret.app_credential.id
  rotation_lambda_arn = aws_lambda_function.rotate_secret.arn

  rotation_rules {
    # 30 日ごとに自動ローテーション。
    # 本番では 30〜90 日が一般的。規制要件によっては 24 時間の場合もある（SCS 頻出）。
    automatically_after_days = 30
  }

  # apply 直後に即時ローテーションを発動する。
  # これにより apply 後すぐに Lambda の 4 フェーズ実行を CloudWatch Logs で確認できる。
  # AWS provider v5.0+ で追加された引数。
  rotate_immediately = true

  # Lambda の権限（aws_lambda_permission）が先に存在する必要がある。
  depends_on = [aws_lambda_permission.allow_secretsmanager]
}
