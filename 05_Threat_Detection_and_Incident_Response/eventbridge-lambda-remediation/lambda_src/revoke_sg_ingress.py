"""
revoke_sg_ingress.py — eventbridge-lambda-remediation

CloudTrail の AuthorizeSecurityGroupIngress（0.0.0.0/0）イベントを受け取り、
追加されたインバウンドルールを自動で取り消すインシデントレスポンス Lambda。

【修復フロー】
1. EventBridge から CloudTrail イベントを受信
2. requestParameters から groupId と追加されたルールを取得
3. cidrIp = 0.0.0.0/0 を含むルールを特定
4. RevokeSecurityGroupIngress でルールを取り消す

【SCS 的観点】
- requestParameters は CloudTrail が記録した「実際に送られたリクエスト」そのもの。
  EventBridge 経由で取得した requestParameters を RevokeSecurityGroupIngress に
  そのまま渡すことで、正確に同じルールを取り消せる。
- Lambda 実行ロールは RevokeSecurityGroupIngress + Describe の最小権限のみ付与する。
"""

import json
import logging

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")


def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    detail = event.get("detail", {})
    request_params = detail.get("requestParameters", {})
    group_id = request_params.get("groupId")
    ip_permissions_raw = request_params.get("ipPermissions", {}).get("items", [])

    if not group_id:
        logger.error("groupId not found in requestParameters")
        return {"statusCode": 400, "body": "groupId not found"}

    user_identity = detail.get("userIdentity", {})
    actor = user_identity.get("arn", "unknown")
    logger.info(
        "AuthorizeSecurityGroupIngress detected. groupId=%s actor=%s", group_id, actor
    )

    # 0.0.0.0/0 を含むルールだけを抽出して取り消す。
    # 0.0.0.0/0 以外のルール（特定の CIDR 許可など）は誤削除しない。
    rules_to_revoke = []
    for rule in ip_permissions_raw:
        ip_ranges = rule.get("ipRanges", {}).get("items", [])
        if any(r.get("cidrIp") == "0.0.0.0/0" for r in ip_ranges):
            perm = {
                "IpProtocol": rule.get("ipProtocol", "-1"),
                "IpRanges": [{"CidrIp": "0.0.0.0/0"}],
            }
            # fromPort / toPort は -1 プロトコル（全ポート）の場合は含めない。
            if rule.get("ipProtocol") != "-1":
                perm["FromPort"] = rule.get("fromPort", 0)
                perm["ToPort"] = rule.get("toPort", 65535)
            rules_to_revoke.append(perm)

    if not rules_to_revoke:
        logger.info("No 0.0.0.0/0 rules found to revoke in groupId=%s", group_id)
        return {"statusCode": 200, "body": "No dangerous rules to revoke"}

    try:
        ec2.revoke_security_group_ingress(
            GroupId=group_id,
            IpPermissions=rules_to_revoke,
        )
        logger.info(
            "Revoked %d dangerous rule(s) from SG: %s", len(rules_to_revoke), group_id
        )
        return {
            "statusCode": 200,
            "body": f"Revoked {len(rules_to_revoke)} rule(s) from {group_id}",
        }

    except Exception as e:
        logger.error(
            "Failed to revoke rules for groupId=%s: %s", group_id, str(e)
        )
        raise
