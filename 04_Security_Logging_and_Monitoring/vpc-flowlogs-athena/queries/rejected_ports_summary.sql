-- REJECT されたポートの集計（インターネットスキャンの構造を把握する）
-- どのポートが集中的に叩かれているかを確認する。
-- SSH(22)・RDP(3389)・HTTP(80) 等が上位に来る場合、ボットやスキャナーによる
-- 自動探索が行われている。SG でインバウンドを全拒否していなければ即座に侵害される。
SELECT
  dstport,
  count(*)     AS request_count,
  count(DISTINCT srcaddr) AS unique_src_ips
FROM "${db_name}"."vpc_flow_logs"
WHERE
  action = 'REJECT'
  AND year  = year(current_date)
  AND month = month(current_date)
  AND day   = day(current_date)
GROUP BY dstport
ORDER BY request_count DESC
LIMIT 20;
