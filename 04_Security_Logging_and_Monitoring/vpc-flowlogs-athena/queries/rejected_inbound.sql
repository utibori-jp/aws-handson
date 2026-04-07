-- 外部からの REJECT ログ（ポートスキャン・接続試行の確認）
-- ローカルから以下を実行した後にこのクエリを流す。
--   curl http://<public_ip>     # ポート 80 が REJECT される
--   nmap -Pn <public_ip>        # 各ポートへのスキャンが REJECT される
--
-- ※ dstaddr はプライベート IP（パブリック IP ではない）で記録される点に注意。
--
-- 【結果の見方】
-- srcaddr には自分のIPアドレス以外の見知らぬIPが多数含まれているはず。
-- これらは Shodan・Censys などのスキャナーや世界中のボットネットが、
-- インターネット上の全パブリックIPを機械的にスキャンしているもの。
-- パブリックIPを持つインスタンスは存在が公開された瞬間から無差別スキャンの対象になる。
-- SG でインバウンドを全拒否しているから REJECT で止まっているが、
-- SSH(22) や RDP(3389) を開けていれば、ブルートフォース攻撃が即座に始まる。
-- 「パブリックIPを持つリソースは常にスキャンされている前提で設計する」ことが重要。
SELECT
  srcaddr,
  dstaddr,
  srcport,
  dstport,
  protocol,
  action,
  from_unixtime(start) AS start_time,
  instance_id
FROM "${db_name}"."vpc_flow_logs"
WHERE
  action  = 'REJECT'
  AND year  = year(current_date)
  AND month = month(current_date)
  AND day   = day(current_date)
ORDER BY start_time DESC
LIMIT 100;
