CREATE OR REPLACE TABLE sales01.customers (
  customer_id INT64,      -- 12345, etc
  customer_name STRING,   -- "田中 正雄", "高橋 直子", etc
  birthday DATE,
  gender STRING,          -- "male" or "female"
  prefecture STRING,      -- "東京都", "北海道", "大阪府", etc
  is_premium BOOL
)
CLUSTER BY customer_id;
