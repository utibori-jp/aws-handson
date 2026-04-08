"""
remediate_iam_key.py — guardduty-and-remediation

GuardDuty の IAM 侵害系フィンディング（UnauthorizedAccess:IAMUser/* など）を受け取り、
侵害された IAM アクセスキーを即時無効化する。

【修復フロー】
1. EventBridge から GuardDuty フィンディングイベントを受け取る
2. フィンディングから侵害されたアクセスキー ID とユーザー名を抽出する
3. iam:UpdateAccessKey で該当キーを Inactive に変更する
4. SNS で修復完了通知を送信する
5. 修復結果を CloudWatch Logs に記録する（監査証跡）

【重要：サンプルフィンディングでの動作】
aws guardduty create-sample-findings で生成されるフィンディングには
実在しないダミーのユーザー名・キー ID が含まれる。
そのため UpdateAccessKey は NoSuchEntityException で失敗するが、
Lambda の実行フロー・ログ記録自体は確認できる。
"""
import boto3
import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client("sns")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")


def lambda_handler(event, context):
    logger.info(f"Received GuardDuty finding event: {json.dumps(event)}")

    detail = event.get("detail", {})
    finding_type = detail.get("type", "Unknown")
    finding_id = detail.get("id", "Unknown")
    severity = detail.get("severity", 0)

    logger.info(f"Finding Type: {finding_type}, ID: {finding_id}, Severity: {severity}")

    # フィンディングから侵害された IAM アクセスキー情報を抽出する。
    resource = detail.get("resource", {})
    access_key_details = resource.get("accessKeyDetails", {})
    access_key_id = access_key_details.get("accessKeyId")
    user_name = access_key_details.get("userName")

    if not access_key_id or not user_name:
        logger.warning(
            f"No accessKeyDetails found in finding {finding_id}. "
            "This finding type may not have IAM key information."
        )
        return {"status": "skipped", "reason": "No accessKeyDetails in finding"}

    logger.info(f"Target: UserName={user_name}, AccessKeyId={access_key_id}")

    # IAM アクセスキーを無効化する。
    iam = boto3.client("iam")
    try:
        iam.update_access_key(
            UserName=user_name,
            AccessKeyId=access_key_id,
            Status="Inactive",
        )
        logger.info(
            f"SUCCESS: Disabled AccessKey {access_key_id} for user {user_name}. "
            f"GuardDuty finding ID: {finding_id}"
        )

        message = (
            f"[Auto-Remediation] IAM access key disabled.\n"
            f"UserName: {user_name}\n"
            f"AccessKeyId: {access_key_id}\n"
            f"FindingType: {finding_type}\n"
            f"FindingId: {finding_id}\n"
            f"Severity: {severity}\n"
            f"Note: Review GuardDuty console and rotate credentials if needed."
        )
        _publish_sns(subject="[GuardDuty Remediation] IAM Key Disabled", message=message)

        return {
            "status": "remediated",
            "action": "DisableAccessKey",
            "user": user_name,
            "key_id": access_key_id,
        }

    except iam.exceptions.NoSuchEntityException:
        # サンプルフィンディングのダミーユーザーは実在しないため、このパスを通る。
        # 本番環境では実在するユーザーに対して実行されるため成功する。
        logger.warning(
            f"User '{user_name}' or key '{access_key_id}' does not exist. "
            "This is expected when using GuardDuty sample findings (dummy users)."
        )
        return {"status": "not_found", "user": user_name, "key_id": access_key_id}

    except Exception as e:
        logger.error(f"Failed to disable key {access_key_id}: {e}")
        raise


def _publish_sns(subject, message):
    if not SNS_TOPIC_ARN:
        return
    try:
        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message)
        logger.info("SNS notification sent: %s", subject)
    except Exception as e:
        logger.warning("SNS publish failed (non-fatal): %s", str(e))
