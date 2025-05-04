SELECT
  order_id,
  date_time,
  customer_name,
  product_name,
  revenue,
  cost * quantity as naive_revenue
FROM sales01.joined_sales
WHERE
  customer_name IS NOT NULL
  AND product_name IS NOT NULL
  AND cost IS NOT NULL
  AND quantity IS NOT NULL
ORDER BY naive_revenue DESC;
