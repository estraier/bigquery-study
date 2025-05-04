CREATE OR REPLACE TABLE sales01.joined_sales AS (
  SELECT
    s.order_id,
    s.date_time,
    CAST(JSON_EXTRACT_SCALAR(s.payload, '$.quantity') AS INT64) AS quantity,
    CAST(JSON_EXTRACT_SCALAR(s.payload, '$.revenue') AS INT64) AS revenue,
    CAST(JSON_EXTRACT_SCALAR(s.payload, '$.is_proper') AS BOOL) AS is_proper,
    c.customer_id,
    c.customer_name,
    c.birthday,
    c.gender,
    c.prefecture,
    c.is_premium,
    p.product_id,
    p.product_name,
    p.product_category,
    p.cost
  FROM
    sales01.sales AS s
  LEFT JOIN
    sales01.customers AS c
  ON
    CAST(JSON_EXTRACT_SCALAR(s.payload, '$.customer_id') AS INT64) = c.customer_id
  LEFT JOIN
    sales01.products AS p
  ON
    CAST(JSON_EXTRACT_SCALAR(s.payload, '$.product_id') AS INT64) = p.product_id
)
