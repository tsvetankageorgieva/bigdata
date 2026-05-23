-- създаване на таблица за клиенти
CREATE TABLE customers (
    customer_id INT NOT NULL,
    name VARCHAR(50) NULL,
    age INT NULL,
    purchase_amount DECIMAL(10,2) NULL,
    product_category VARCHAR(30) NULL,
    purchase_date DATE NULL
);
-- попълване с примерни данни
INSERT INTO customers (customer_id, name, age, purchase_amount, product_category, purchase_date) VALUES
(1, 'Ivan Petrov', 25, 100, 'Electronics', '2025-01-05'),
(2, 'Maria Ivanova', 30, 200, 'Clothing', '2025-01-06'),
(2, 'Maria Ivanova', 30, 200, 'Clothing', '2025-01-06'), -- duplicate
(3, 'Georgi Georgiev', 40, 150, 'Books', '2025-01-07'),
(4, 'Anna Koleva', -5, 50, 'Electronics', '2025-01-08'), -- invalid age
(5, NULL, 28, NULL, 'Clothing', '2025-01-09'), -- missing name, missing amount
(6, 'Petar Dimitrov', 35, 300, 'Books', '2025-01-10'),
(7, 'Ivan Petrov', NULL, 120, 'Electronics', '2025-01-11'), -- missing age
(8, 'Maria Ivanova', 32, 250, 'Clothing', NULL), -- missing date
(9, 'Georgi Georgiev', 40, 180, 'Electronics', '2025-01-12');

SELECT * FROM customers;
-- Изтриване на редове с липсващи стойности в name
DELETE FROM customers
WHERE name IS NULL OR name = '';

-- Попълване на празни суми със средна стойност
UPDATE customers
SET purchase_amount = (SELECT AVG(purchase_amount)
                       FROM customers)
WHERE purchase_amount IS NULL;

-- Попълване на липсваща възраст с медиана
UPDATE customers
SET age = (SELECT DISTINCT PERCENTILE_CONT(0.5) 
                  WITHIN GROUP (ORDER BY age) OVER() AS median_age
           FROM customers)
WHERE age IS NULL;

-- Попълване на липсващо име с 'Unknown'
UPDATE customers
   SET name = 'Unknown'
WHERE name IS NULL OR name = '';

--Добавяне и попълване на индикаторна колона за липсващи стойности в purchase_date
ALTER TABLE customers ADD missing_purchase_date_flag bit NOT NULL DEFAULT 1;
UPDATE customers
   SET missing_purchase_date_flag = 
       CASE 
         WHEN purchase_date IS NULL THEN 1
         ELSE 0
       END
WHERE purchase_date IS NULL;

-- Откриване на дубликати
SELECT customer_id, name, age, purchase_amount, product_category, purchase_date,
       COUNT(*) AS cnt
FROM customers
GROUP BY customer_id, name, age, purchase_amount, product_category, purchase_date
HAVING COUNT(*) > 1;
-- или
WITH c AS (SELECT *, ROW_NUMBER() OVER (
            PARTITION BY customer_id, name, age, purchase_amount, 
			             product_category, purchase_date
            ORDER BY customer_id) AS rn
       FROM customers )
SELECT *
FROM c
WHERE rn > 1;
-- Премахване на дубликати (запазваме само един)
WITH Duplicates AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, name, age, purchase_amount, product_category, purchase_date
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM customers
)
DELETE FROM Duplicates
WHERE rn > 1;

-- Откриване на невалидна възраст < 0 и над 120
SELECT *
FROM customers
WHERE age < 0 OR age > 120;

-- Корекция на отрицателна възраст и възраст >120 (например замяна с NULL)
UPDATE customers
   SET age = NULL
WHERE age < 0 OR age > 120;

-- Добавяне на нови колони – ден от седмицата и месец 
SELECT *,
    DATENAME(WEEKDAY, purchase_date) AS day_of_week,
    DATENAME(MONTH, purchase_date) AS month
FROM customers;

-- Кодиране с етикети (label encoding) – всяка категория се заменя с цяло число
WITH categories AS (
    SELECT 
        product_category,
        ROW_NUMBER() OVER (ORDER BY product_category) AS category_encoded
    FROM (
        SELECT DISTINCT product_category 
        FROM customers
        WHERE product_category IS NOT NULL
    ) AS t
)
SELECT p.*, c.category_encoded
FROM customers p
LEFT JOIN categories c
    ON p.product_category = c.product_category;
 
-- Кодиране с бинарни стойности (one-hot encoding)
-- за всяка категория се създава отделна бинарна (0/1) колона.
SELECT customer_id, name, age, purchase_amount, 
       product_category, purchase_date,
    CASE WHEN product_category = 'Electronics' THEN 1 ELSE 0 END AS category_Electronics,
    CASE WHEN product_category = 'Clothing'    THEN 1 ELSE 0 END AS category_Clothing,
    CASE WHEN product_category = 'Books'       THEN 1 ELSE 0 END AS category_Books
FROM customers
-- с pivot
SELECT customer_id, name, age, purchase_amount, purchase_date,
       ISNULL([Electronics], 0) AS category_Electronics,
       ISNULL([Clothing], 0) AS category_Clothing,
       ISNULL([Books], 0) AS category_Books
FROM
(   SELECT customer_id, name, age, purchase_amount, purchase_date, product_category, 1 AS value
    FROM customers
) src
PIVOT
(   MAX(value)
    FOR product_category IN ([Electronics], [Clothing], [Books])
) pvt;


-- Изчисляване на min и max за всяка колона
WITH stats AS (
    SELECT MIN(CAST(age AS float)) AS min_age, MAX(CAST(age AS float)) AS max_age,
           MIN(purchase_amount) AS min_purchase, MAX(purchase_amount) AS max_purchase
    FROM customers )
-- Приложение на Min–Max скалиране
SELECT customer_id, name, age, purchase_amount,
    (age - stats.min_age) / (stats.max_age - stats.min_age) AS age_scaled,
    (purchase_amount - stats.min_purchase) / (stats.max_purchase - stats.min_purchase) AS purchase_scaled,
    product_category, purchase_date
FROM customers
CROSS JOIN stats;

-- стандартизация
WITH stats AS (
    SELECT AVG(age) AS mean_age, STDEV(age) AS std_age,
        AVG(purchase_amount) AS mean_purchase,
        STDEV(purchase_amount) AS std_purchase
    FROM customers )
SELECT customer_id, name, age, purchase_amount,
    (age - stats.mean_age) / stats.std_age AS age_z,
    (purchase_amount - stats.mean_purchase) / stats.std_purchase AS purchase_z,
    product_category, purchase_date
FROM customers
CROSS JOIN stats;

-- отклонения
WITH stats AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY age) OVER () AS Q1_age,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY age) OVER () AS Q3_age,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY purchase_amount) OVER () AS Q1_purchase,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY purchase_amount) OVER () AS Q3_purchase
    FROM customers )
SELECT
    c.*,
    CASE 
        WHEN age < Q1_age - 1.5*(Q3_age-Q1_age) OR age > Q3_age + 1.5*(Q3_age-Q1_age) THEN 1
        ELSE 0
    END AS age_outlier,
    CASE 
        WHEN purchase_amount < Q1_purchase - 1.5*(Q3_purchase-Q1_purchase) OR purchase_amount > Q3_purchase + 1.5*(Q3_purchase-Q1_purchase) THEN 1
        ELSE 0
    END AS purchase_outlier
FROM customers c
CROSS JOIN stats;
