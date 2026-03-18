"""
isolate_ec2.py — EC2 インスタンス隔離 Lambda

GuardDuty の EC2 侵害系フィンディング（Backdoor:EC2/* / CryptoCurrency:EC2/* など）を受け取り、
侵害された EC2 インスタンスのセキュリティグループを「空の隔離 SG」に差し替えてネットワーク隔離する。

【修復フロー】
1. EventBridge から GuardDuty フィンディングイベントを受け取る
2. フィンディングから侵害された EC2 インスタンス ID と VPC ID を抽出する
3. 同一 VPC 内に「インバウンド/アウトバウンドをすべてブロック」する隔離 SG を作成する
4. インスタンスのセキュリティグループを隔離 SG のみに差し替える
5. 修復結果を CloudWatch Logs に記録する（監査証跡）

【設計上の重要な判断：終了（Terminate）ではなく隔離（Isolate）を選んだ理由】
- TerminateInstances をここで実行すると、フォレンジック調査に必要な証拠（メモリ・ディスク）が消える
- インシデントレスポンスの原則：「隔離して保全」してから調査・承認を経て終了する
- SCS 頻出：自動修復の範囲を「最小の影響で最大の保護」に留めるべきという考え方

【重要：サンプルフィンディングでの動作】
aws guardduty create-sample-findings のサンプルには実在しないダミーのインスタンス ID が含まれる。
DescribeInstances が空を返すため隔離処理はスキップされるが、Lambda の実行フロー自体は確認できる。
"""
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

QUARANTINE_SG_NAME_PREFIX = "quarantine"


def lambda_handler(event, context):
    logger.info(f"Received GuardDuty finding event: {json.dumps(event)}")

    detail = event.get("detail", {})
    finding_type = detail.get("type", "Unknown")
    finding_id = detail.get("id", "Unknown")

    logger.info(f"Finding Type: {finding_type}, ID: {finding_id}")

    # フィンディングから侵害された EC2 インスタンス情報を抽出する。
    resource = detail.get("resource", {})
    instance_details = resource.get("instanceDetails", {})
    instance_id = instance_details.get("instanceId")

    if not instance_id:
        logger.warning(f"No instanceDetails in finding {finding_id}. Skipping.")
        return {"status": "skipped", "reason": "No instanceDetails in finding"}

    logger.info(f"Target instance: {instance_id}")

    ec2 = boto3.client("ec2")

    # インスタンスの VPC ID を取得する（隔離 SG を同じ VPC 内に作成するため）。
    instances = ec2.describe_instances(InstanceIds=[instance_id])
    reservations = instances.get("Reservations", [])
    if not reservations:
        logger.warning(
            f"Instance {instance_id} not found. "
            "This is expected when using GuardDuty sample findings (dummy instances)."
        )
        return {"status": "not_found", "instance_id": instance_id}

    instance = reservations[0]["Instances"][0]
    vpc_id = instance.get("VpcId")
    if not vpc_id:
        logger.warning(f"Instance {instance_id} has no VPC ID. Cannot isolate.")
        return {"status": "skipped", "reason": "Instance not in VPC"}

    logger.info(f"Instance {instance_id} is in VPC {vpc_id}")

    # 隔離 SG を作成する（インバウンド/アウトバウンドのデフォルトルールをすべて削除する）。
    quarantine_sg_id = _get_or_create_quarantine_sg(ec2, vpc_id, instance_id)

    # インスタンスのセキュリティグループを隔離 SG のみに差し替える。
    ec2.modify_instance_attribute(
        InstanceId=instance_id,
        Groups=[quarantine_sg_id],
    )

    logger.info(
        f"SUCCESS: Isolated instance {instance_id}. "
        f"Security group replaced with quarantine SG {quarantine_sg_id}. "
        f"GuardDuty finding ID: {finding_id}"
    )

    return {
        "status": "remediated",
        "action": "IsolateEC2",
        "instance_id": instance_id,
        "quarantine_sg_id": quarantine_sg_id,
    }


def _get_or_create_quarantine_sg(ec2, vpc_id, instance_id):
    """隔離用セキュリティグループを取得または作成する。"""
    sg_name = f"{QUARANTINE_SG_NAME_PREFIX}-{instance_id}"

    # 既存の隔離 SG を検索する（冪等性：複数回実行しても同じ結果になるように）。
    existing = ec2.describe_security_groups(
        Filters=[
            {"Name": "group-name", "Values": [sg_name]},
            {"Name": "vpc-id", "Values": [vpc_id]},
        ]
    )
    if existing["SecurityGroups"]:
        sg_id = existing["SecurityGroups"][0]["GroupId"]
        logger.info(f"Using existing quarantine SG: {sg_id}")
        return sg_id

    # 新規作成：インバウンド/アウトバウンドルールを一切持たない空の SG。
    response = ec2.create_security_group(
        GroupName=sg_name,
        Description=f"Quarantine SG for compromised instance {instance_id} (auto-created by GuardDuty remediation)",
        VpcId=vpc_id,
    )
    sg_id = response["GroupId"]

    # 新規 SG のデフォルトアウトバウンドルール（全許可）を削除してすべてのトラフィックをブロックする。
    ec2.revoke_security_group_egress(
        GroupId=sg_id,
        IpPermissions=[
            {"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}
        ],
    )

    ec2.create_tags(
        Resources=[sg_id],
        Tags=[
            {"Key": "Name", "Value": sg_name},
            {"Key": "Purpose", "Value": "GuardDuty-Quarantine"},
            {"Key": "SourceInstance", "Value": instance_id},
        ],
    )

    logger.info(f"Created new quarantine SG: {sg_id}")
    return sg_id
