# =============================================================================
# conformance_pack.tf — config-conformance-pack
# SCS 頻出の Config ルールを Conformance Pack としてまとめて適用する。
#
# 【Conformance Pack とは】
# 複数の Config ルールとそれに対する修復アクションをまとめた「パッケージ」。
# CloudFormation テンプレート形式（YAML/JSON）で定義し、
# アカウント単位または Organizations 全体に適用できる（SCS 頻出）。
#
# 【評価モード（SCS 頻出の対比）】
# - 変更時トリガー（ConfigurationItemChangeNotification）:
#     リソースの設定変更があったときに即時評価する。
# - 定期トリガー（ScheduledNotification）:
#     1h / 3h / 6h / 12h / 24h の間隔で定期的に評価する。
#   → 動的に変わらない設定（MFA 有効化、ルートの MFA など）は定期評価が向いている。
#
# 【実装方法】
# S3 バケットの YAML を参照する方法とインライン template_body の2通りがある。
# このモジュールは S3 依存を排除するためインラインで定義する。
# =============================================================================

resource "aws_config_conformance_pack" "scs_checks" {
  name = "${var.project_name}-scs-security-checks"

  # Config レコーダーが有効化されてから Conformance Pack を適用する。
  depends_on = [aws_config_configuration_recorder_status.main]

  # Conformance Pack のテンプレート（CloudFormation 形式の YAML）。
  # 各ルールの SourceIdentifier はマネージドルール識別子（大文字スネークケース）を使用する。
  template_body = <<-YAML
    Resources:

      # ---
      # S3 セキュリティ
      # ---

      S3BucketSSEEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-server-side-encryption-enabled
          Description: "S3 バケットにサーバーサイド暗号化が有効かどうかを確認する（CIS / SCS 頻出）"
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED

      S3BucketPublicAccessProhibited:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-public-access-prohibited
          Description: "S3 バケットのパブリックアクセスブロックが有効かどうかを確認する"
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_PUBLIC_ACCESS_PROHIBITED

      # ---
      # IAM セキュリティ
      # ---

      IamUserMfaEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: iam-user-mfa-enabled
          Description: "すべての IAM ユーザーに MFA が有効化されているか確認する"
          Source:
            Owner: AWS
            SourceIdentifier: IAM_USER_MFA_ENABLED

      IamPasswordPolicy:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: iam-password-policy
          Description: "アカウントパスワードポリシーが最低要件を満たしているか確認する"
          Source:
            Owner: AWS
            SourceIdentifier: IAM_PASSWORD_POLICY
          InputParameters:
            RequireUppercaseCharacters: "true"
            RequireLowercaseCharacters: "true"
            RequireSymbols: "true"
            RequireNumbers: "true"
            MinimumPasswordLength: "14"
            PasswordReusePrevention: "24"
            MaxPasswordAge: "90"

      # ---
      # CloudTrail / ログ
      # ---

      CloudTrailEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cloudtrail-enabled
          Description: "CloudTrail がアカウントで有効化されているか確認する（CIS 2.1）"
          Source:
            Owner: AWS
            SourceIdentifier: CLOUD_TRAIL_ENABLED

      CloudTrailLogFileValidationEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cloud-trail-log-file-validation-enabled
          Description: "CloudTrail のログファイル整合性検証が有効か確認する（CIS 2.2 / 改ざん検知）"
          Source:
            Owner: AWS
            SourceIdentifier: CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED

      # ---
      # ルートアカウント
      # ---

      RootAccountMfaEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: root-account-mfa-enabled
          Description: "ルートアカウントに MFA が設定されているか確認する（CIS 1.1 / SCS 最頻出）"
          Source:
            Owner: AWS
            SourceIdentifier: ROOT_ACCOUNT_MFA_ENABLED

      RootAccountHardwareMfaEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: root-account-hardware-mfa-enabled
          Description: "ルートアカウントにハードウェア MFA が設定されているか確認する（CIS 1.2）"
          Source:
            Owner: AWS
            SourceIdentifier: ROOT_ACCOUNT_HARDWARE_MFA_ENABLED
  YAML
}
