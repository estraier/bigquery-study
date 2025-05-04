CREATE OR REPLACE TABLE sales01.products (
  product_id INT64,         -- 12345, etc
  product_name STRING,      -- "大根", "豆腐", "ハム", etc
  product_category STRING,  -- "野菜", "惣菜", "精肉", etc
  cost FLOAT64              -- 80.5, 2923.2, 900, etc
)
CLUSTER BY product_id;
