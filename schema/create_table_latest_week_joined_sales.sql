CREATE OR REPLACE TABLE sales01.latest_week_joined_sales AS (
  WITH max_ts AS (
    SELECT MAX(date_time) AS last_ts
    FROM sales01.joined_sales
  )
  SELECT *
  FROM sales01.joined_sales
  WHERE date_time BETWEEN TIMESTAMP_SUB((SELECT last_ts FROM max_ts), INTERVAL 7 DAY)
                      AND (SELECT last_ts FROM max_ts)
);
