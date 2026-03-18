"""
cancel_kms_deletion.py — eventbridge-lambda-remediation

CloudTrail の ScheduleKeyDeletion イベントを受け取り、
KMS CMK の削除予約を自動でキャンセルするインシデントレスポンス Lambda。

【修復フロー】
1. EventBridge から CloudTrail イベントを受信
2. requestParameters.keyId を取得
3. CancelKeyDeletion で削除予約を取り消す
4. EnableKey でキーを再び有効化する
   （ScheduleKeyDeletion はキーを自動的に無効化するため再有効化が必要）

【SCS 的観点】
- 自動修復は「人間が承認するまでの時間稼ぎ」として設計する。
  最終的な判断（本当に削除すべきか）は人間が行う。
- Lambda 実行ロールは CancelKeyDeletion + EnableKey の最小権限のみ付与する。
"""

import json
import logging

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

kms = boto3.client("kms")


def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    detail = event.get("detail", {})
    request_params = detail.get("requestParameters", {})
    key_id = request_params.get("keyId")

    if not key_id:
        logger.error("keyId not found in requestParameters")
        return {"statusCode": 400, "body": "keyId not found"}

    user_identity = detail.get("userIdentity", {})
    actor = user_identity.get("arn", "unknown")
    logger.info("ScheduleKeyDeletion detected. keyId=%s actor=%s", key_id, actor)

    try:
        kms.cancel_key_deletion(KeyId=key_id)
        logger.info("CancelKeyDeletion succeeded for key: %s", key_id)

        # ScheduleKeyDeletion はキーを自動的に無効化するため再有効化する。
        # この操作がないとキーは使用不能のまま残り、暗号化データにアクセスできなくなる。
        kms.enable_key(KeyId=key_id)
        logger.info("EnableKey succeeded for key: %s", key_id)

        return {
            "statusCode": 200,
            "body": f"Cancelled deletion and re-enabled key: {key_id}",
        }

    except kms.exceptions.NotFoundException:
        logger.error("KMS key not found: %s", key_id)
        return {"statusCode": 404, "body": f"Key not found: {key_id}"}

    except Exception as e:
        logger.error("Remediation failed for key %s: %s", key_id, str(e))
        raise
