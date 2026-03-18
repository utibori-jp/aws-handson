"""
rotate_secret.py — Secrets Manager カスタムローテーター Lambda

Secrets Manager のローテーションライフサイクル（4フェーズ）を実装する。

【4フェーズの役割】
  createSecret  : AWSPENDING バージョンに新しい認証情報を生成・保存する
  setSecret     : 実際のサービス（DB など）の認証情報を新しいものに更新する ← ⚠️ このモジュールはスタブ
  testSecret    : 新しい認証情報で実際のサービスに接続確認する ← ⚠️ このモジュールはスタブ
  finishSecret  : AWSPENDING を AWSCURRENT に昇格させ、旧バージョンを AWSPREVIOUS に降格する

⚠️ setSecret と testSecret はスタブ実装です
   このモジュールはローテーションメカニズムの学習が目的のため、
   実際のデータベースや外部サービスには接続しません。
   - setSecret: DB/サービスへの認証情報更新をスキップしてログのみ出力
   - testSecret: 実際の疎通確認をスキップし、JSON 構造チェックのみ実施

   本番環境では setSecret でサービスの認証情報を更新し、
   testSecret で実際に接続確認を行う実装が必要です。
"""
import boto3
import json
import logging
import random
import string

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    logger.info(f"Rotation step: {step}, SecretId: {arn}, Token: {token}")

    client = boto3.client("secretsmanager")

    # ローテーションが有効か・バージョンが正しい状態かを確認する（定型チェック）。
    metadata = client.describe_secret(SecretId=arn)
    if not metadata.get("RotationEnabled"):
        raise ValueError(f"Secret {arn} is not enabled for rotation")

    versions = metadata.get("VersionIdsToStages", {})
    if token not in versions:
        raise ValueError(f"Secret version {token} has no stage for rotation of {arn}")

    if "AWSCURRENT" in versions[token]:
        logger.info(f"Version {token} is already AWSCURRENT. Nothing to do.")
        return
    elif "AWSPENDING" not in versions[token]:
        raise ValueError(f"Secret version {token} is not in AWSPENDING stage")

    # 各フェーズに対応するハンドラを呼び出す。
    if step == "createSecret":
        create_secret(client, arn, token)
    elif step == "setSecret":
        set_secret(client, arn, token)
    elif step == "testSecret":
        test_secret(client, arn, token)
    elif step == "finishSecret":
        finish_secret(client, arn, token)
    else:
        raise ValueError(f"Invalid rotation step: {step}")


def create_secret(client, arn, token):
    """
    フェーズ 1: AWSPENDING バージョンに新しい認証情報を生成・保存する。
    このフェーズはまだ実際のサービスには何も変更を加えない。
    """
    # AWSPENDING が既に存在する場合はスキップ（冪等性）。
    try:
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        logger.info("AWSPENDING already exists. Skipping createSecret.")
        return
    except client.exceptions.ResourceNotFoundException:
        pass

    # 現在の AWSCURRENT から構造を引き継ぎ、パスワードだけを新しい値に差し替える。
    current_secret = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")["SecretString"]
    )
    new_password = _generate_password()
    new_secret = dict(current_secret)
    new_secret["password"] = new_password

    client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(new_secret),
        VersionStages=["AWSPENDING"],
    )
    logger.info(f"createSecret: Created AWSPENDING version with new password for user '{new_secret['username']}'")


def set_secret(client, arn, token):
    """
    フェーズ 2: 実際のサービスの認証情報を新しいものに更新する。

    ⚠️ スタブ実装 — 実際のサービスには接続しません。
    本番では ここで DB の ALTER USER / UPDATE credentials を実行する。
    例:
        conn = psycopg2.connect(host=..., user=current['username'], password=current['password'])
        conn.execute(f"ALTER USER {username} WITH PASSWORD '{new_password}'")
    """
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")["SecretString"]
    )
    logger.info(
        f"setSecret: [STUB] Would update credentials for user '{pending['username']}' in the target service. "
        "Skipped — no real target service in this handson module."
    )


def test_secret(client, arn, token):
    """
    フェーズ 3: 新しい認証情報で実際のサービスに接続確認する。

    ⚠️ スタブ実装 — 実際のサービスへの疎通確認は行いません。
    このフェーズで接続確認をスキップしているため、
    「新しいパスワードが実際に使えるか」の検証はできていません。

    本番では ここで新しい認証情報を使って実際に DB 接続を試み、
    失敗した場合は例外を raise してローテーションを中断させる必要があります。
    例:
        conn = psycopg2.connect(host=..., user=new['username'], password=new['password'])
        conn.execute("SELECT 1")  # 接続確認
    """
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")["SecretString"]
    )

    # 最低限の検証: JSON として読めること・必須フィールドが存在すること。
    assert "username" in pending, "Required field 'username' missing from AWSPENDING secret"
    assert "password" in pending, "Required field 'password' missing from AWSPENDING secret"

    logger.warning(
        "testSecret: [STUB] JSON structure check passed. "
        "Actual service connection test SKIPPED — no real target service. "
        "In production, verify new credentials against the target service here."
    )


def finish_secret(client, arn, token):
    """
    フェーズ 4: AWSPENDING を AWSCURRENT に昇格させる。
    旧 AWSCURRENT は自動的に AWSPREVIOUS に降格される（フォールバック用に保持）。
    """
    metadata = client.describe_secret(SecretId=arn)
    current_version = None

    for version_id, stages in metadata["VersionIdsToStages"].items():
        if "AWSCURRENT" in stages:
            if version_id == token:
                logger.info("finishSecret: Version is already AWSCURRENT. Nothing to do.")
                return
            current_version = version_id
            break

    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info(
        f"finishSecret: Promoted version {token} to AWSCURRENT. "
        f"Previous version {current_version} moved to AWSPREVIOUS."
    )


def _generate_password(length: int = 32) -> str:
    """ランダムな強力パスワードを生成する。"""
    chars = string.ascii_letters + string.digits + "!@#$%^&*()-_=+"
    return "".join(random.choice(chars) for _ in range(length))
