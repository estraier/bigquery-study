SELECT order_id, product_name, customer_name, revenue
FROM sales01.joined_sales
WHERE order_id IN (1, 6)

/*
order_id,product_name,customer_name,revenue
1,けん玉,山下 翼,119720
6,電気毛布,田中 浩,71218
*/
