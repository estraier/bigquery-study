SELECT
  DATE(date_time) AS sales_date,
  product_category,
  SUM(revenue) AS total_revenue
FROM
  sales01.joined_sales
WHERE
  revenue IS NOT NULL
  AND product_category IS NOT NULL
GROUP BY
  sales_date, product_category
ORDER BY
  sales_date, product_category;
