/*
 * Analytical Query Script
 *
 * This file contains a collection of analytical SQL queries for the coffee shop analytics
 * schema. It is designed to explore sales patterns, store performance, category and product
 * trends, temporal behavior, geospatial metrics, and transaction-level customer basket analysis.
 *
 * Key areas covered:
 * - daily store revenue and weekday performance
 * - location-based revenue and geographic rankings
 * - hourly sales peaks and sales density
 * - category and product variant trends over time
 * - store-product performance and store ranking with segmentation
 *
 * The script also defines a utility view and helper functions to classify store performance
 * by revenue and quantity sold.
 */

-- 1. Sales by Store per Day
SELECT 
	tr.store_id, 
	date, 
	SUM(quantity*unit_price) AS revenue_by_store_per_day
FROM analytics.transactions tr
GROUP BY tr.store_id, date
;

-- Performance per Day of Week
SELECT 
    EXTRACT(DOW FROM date) AS day_of_week,
    TO_CHAR(date, 'Day') AS weekday_name,
    SUM(quantity * unit_price) AS total_sales,
    SUM(quantity) AS total_units_sold,
    COUNT(DISTINCT transaction_id) AS num_transactions
FROM analytics.transactions
GROUP BY day_of_week, weekday_name
ORDER BY total_sales DESC;

-- Performance by Store/Location per Day of Week
SELECT 
    s.store_id,
    sl.location_name,
    EXTRACT(DOW FROM t.date) AS day_of_week,
    TO_CHAR(t.date, 'Day') AS weekday_name,
    SUM(t.quantity * t.unit_price) AS total_sales,
    SUM(t.quantity) AS total_units_sold,
    COUNT(DISTINCT t.transaction_id) AS num_transactions
FROM analytics.transactions t
JOIN analytics.stores s ON t.store_id = s.store_id
JOIN analytics.store_locations sl ON s.location_id = sl.location_id
GROUP BY s.store_id, sl.location_name, day_of_week, weekday_name
ORDER BY s.store_id, day_of_week;


-- 2. Store Location + Date        
SELECT 
	sl.location_name, 
	t.date, 
	SUM(t.quantity * t.unit_price) AS total_revenue
FROM analytics.transactions t
JOIN analytics.stores s ON t.store_id = s.store_id
JOIN analytics.store_locations sl ON s.location_id = sl.location_id
-- WHERE t.date BETWEEN '2026-01-01' AND '2026-01-31'
WHERE t.date BETWEEN '2023-01-01' AND '2023-01-31'
GROUP BY sl.location_name, t.date
ORDER BY sl.location_name
;

-- Without index: Sequential scan + spatial join.

-- With idx_transactions_store_date + GIST index on geom: PostgreSQL uses both indexes to filter by date and spatial boundaries efficiently.

--  3. Peak Hours Analysis
SELECT 
	*
FROM analytics.hourly_sales	
ORDER BY total_sales DESC
;

--  peak hours by stores
SELECT 
	location_name,
	EXTRACT(HOUR FROM time) AS hour, 
	SUM(quantity*unit_price) AS total_sales
FROM analytics.transactions t
JOIN analytics.sales_by_store slbst ON t.store_id = slbst.store_id
GROUP BY location_name, hour
ORDER BY total_sales DESC
LIMIT 10
;


-- 4. Sales by Category per Store
SELECT 
	c.category, 
	t.store_id, 
	location_name,
	SUM(t.quantity*t.unit_price) AS revenue_per_category
FROM analytics.transactions t
JOIN analytics.stores s ON t.store_id = s.store_id
JOIN analytics.store_locations sl ON sl.location_id = s.location_id
JOIN analytics.products_variants pv ON t.product_variant_id = pv.product_variant_id
JOIN analytics.products p ON pv.product_id = p.product_id
JOIN analytics.categories c ON p.category_id = c.category_id
GROUP BY t.store_id, c.category, location_name 
;


-- 5. Category Trends Over Time
SELECT 
	c.category, 
	t.date, 
	SUM(t.quantity*t.unit_price) AS revenue_by_category_and_date
FROM analytics.transactions t
JOIN analytics.products_variants pv ON t.product_variant_id = pv.product_variant_id
JOIN analytics.products p ON pv.product_id = p.product_id
JOIN analytics.categories c ON p.category_id = c.category_id
GROUP BY c.category, t.date
;


-- 6. Product Variant Trends    
SELECT
    t.date,
    pv.product_variant,
    SUM(t.quantity) AS total_units_sold,
    SUM(t.quantity * t.unit_price) AS total_revenue_per_product
FROM analytics.transactions t
JOIN analytics.products_variants pv ON t.product_variant_id = pv.product_variant_id
GROUP BY t.date, pv.product_variant 
ORDER BY t.date, pv.product_variant;

SELECT
    pv.product_variant,
    SUM(t.quantity) AS total_units_sold,
    SUM(t.quantity * t.unit_price) AS total_revenue_per_product
FROM analytics.transactions t
JOIN analytics.products_variants pv ON t.product_variant_id = pv.product_variant_id
GROUP BY  pv.product_variant 
ORDER BY  pv.product_variant;


-- 7. Store + Product Variant    
SELECT 
	t.store_id, 
	pv.product_variant, 
	SUM(t.quantity) AS units_sold
FROM analytics.transactions t
JOIN analytics.products_variants pv ON t.product_variant_id = pv.product_variant_id
GROUP BY t.store_id, pv.product_variant
ORDER BY units_sold DESC;


-- 8. Area of each Store Location
SELECT 
	location_name, 
	ST_Area(geom::geography)/1000000 AS area_km2
FROM analytics.store_location_summary;


-- 9. Sales Density 
SELECT
	*
FROM analytics.sales_density;


-- 10. Customer Basket Analysis
SELECT DISTINCT
	transaction_id,
	product_variant
FROM analytics.transactions t
JOIN analytics.products_variants pv ON t.product_variant_id = pv.product_variant_id
GROUP BY transaction_id, product_variant
;


-- 11. Average Unit Price Trends
SELECT 
	*
FROM analytics.price_trends;

SELECT
	product_variant, 
	date,
	avg_price
FROM analytics.price_trends pt
JOIN analytics.products_variants pv ON pt.product_variant_id = pv.product_variant_id
WHERE pt.product_variant_id = 82  -- I Need My Bean! Diner mug
ORDER BY date
;


-- 12. Store Performance Ranking
CREATE OR REPLACE VIEW store_ranks_by_quantity_revenue AS
SELECT
	location_name,
	total_units_sold,
	total_revenue,
	quantity_rank,
	revenue_rank
FROM analytics.store_rankings sr
JOIN analytics.stores s ON s.store_id = sr.store_id
JOIN analytics.store_locations sl ON sl.location_id = s.location_id
;

---- Store Revenue segmentation function, mapping total revenue into Low/Medium/High 
---- based on High/Low thresholds calculated in 06_zscore_analysis.py.
CREATE OR REPLACE FUNCTION store_revenue_performance ( p_total_revenue numeric(10,2) )
RETURNS TEXT
LANGUAGE sql
AS $$
    SELECT 
		CASE
            WHEN p_total_revenue < 231296.25 THEN 'Low'
            WHEN p_total_revenue BETWEEN 231296.25 AND 234578.63 THEN 'Medium'
            ELSE 'High'
        END;
	;
$$;

---- Store Quantity segmentation function, mapping total quantity sold into Developing/Rising/Elite 
---- based on High/Low thresholds calculated in 06_zscore_analysis.py.
CREATE OR REPLACE FUNCTION sold_quantity_per_store ( p_total_units_sold BIGINT )
RETURNS TEXT
LANGUAGE sql
AS $$
    SELECT 
		CASE
            WHEN p_total_units_sold < 71273.92 THEN 'Developing'
            WHEN p_total_units_sold BETWEEN 71273.92 AND 71706.08 THEN 'Rising'
            ELSE 'Elite'
        END;
	;
$$;


SELECT 
	location_name,
	quantity_rank,
	sold_quantity_per_store(total_units_sold) AS seller_by_quantity,
	revenue_rank,
	store_revenue_performance(total_revenue) AS seller_by_revenue
FROM store_ranks_by_quantity_revenue;
