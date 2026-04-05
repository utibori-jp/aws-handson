-- EC2 から外部への自動アウトバウンドトラフィック
-- インスタンス起動後に SSM Agent のハートビートや dnf リポジトリへのアクセスなど、
-- 自動的に発生するアウトバウンド通信が記録される。
--
-- instance_id に terraform output instance_id の値を入れて実行すること。
SELECT
  srcaddr,
  dstaddr,
  dstport,
  protocol,
  bytes,
  packets,
  action,
  from_unixtime(start) AS start_time
FROM "${db_name}"."vpc_flow_logs"
WHERE
  instance_id = 'i-xxxxxxxxxxxxxxxxx'  -- ← terraform output instance_id の値に書き換える
  AND action = 'ACCEPT'
  AND year  = year(current_date)
  AND month = month(current_date)
  AND day   = day(current_date)
ORDER BY start_time DESC
LIMIT 100;
