SELECT
  p.product_id,
  p.product_name,
  SUM(CAST(JSON_EXTRACT_SCALAR(s.payload, '$.revenue') AS INT64)) AS total_revenue
FROM
  sales01.sales AS s
JOIN
  sales01.customers AS c
  ON CAST(JSON_EXTRACT_SCALAR(s.payload, '$.customer_id') AS INT64) = c.customer_id
JOIN
  sales01.products AS p
  ON CAST(JSON_EXTRACT_SCALAR(s.payload, '$.product_id') AS INT64) = p.product_id
WHERE
  c.prefecture IN ('東京都', '神奈川県', '埼玉県', '千葉県', '栃木県', '群馬県', '茨城県')
  AND c.gender = 'female'
  AND JSON_EXTRACT_SCALAR(s.payload, '$.revenue') IS NOT NULL
GROUP BY
  p.product_id,
  p.product_name
ORDER BY
  total_revenue DESC;
