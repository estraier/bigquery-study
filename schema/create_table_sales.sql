CREATE OR REPLACE TABLE sales01.sales (
  order_id INT64 NOT NULL,
  date_time TIMESTAMP NOT NULL,
  log_source STRING,
  payload JSON NOT NULL
)
PARTITION BY DATE(date_time)
CLUSTER BY order_id;
