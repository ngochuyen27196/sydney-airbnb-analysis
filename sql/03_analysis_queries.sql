/* =====================================================================
   STEP 3 - Analysis queries (Part 1)
   Tip: press Ctrl+T first (Results to Text), then select everything and
   press F5. All results appear in one pane and you can copy-paste them.
   Press Ctrl+D to go back to Results to Grid.

   Price rule used in every price statistic: price_flag = 'OK'
   (price is present and below 2000 per night). Missing prices and the
   448 outliers are excluded, and this is stated in the dashboard notes.
   ===================================================================== */
USE AirbnbSydney;
GO

PRINT '=== Q1a: market overview ===';
SELECT COUNT(*)                                                   AS listings,
       SUM(CASE WHEN price IS NOT NULL THEN 1 ELSE 0 END)         AS priced_listings,
       SUM(CASE WHEN price_flag = 'OK' THEN 1 ELSE 0 END)         AS priced_ok,
       CAST(AVG(CASE WHEN price_flag = 'OK' THEN price END) AS DECIMAL(10,2))             AS avg_price_ok,
       CAST(AVG(CASE WHEN price_flag = 'OK' THEN est_revenue_l365d END) AS DECIMAL(12,0)) AS avg_revenue_ok,
       CAST(AVG(CAST(est_occupancy_nights_l365d AS FLOAT)) AS DECIMAL(6,1))               AS avg_nights_booked,
       CAST(AVG(review_score_rating) AS DECIMAL(4,2))                                     AS avg_rating
FROM dbo.dim_listing;

PRINT '=== Q1b: median price ===';
SELECT DISTINCT
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) OVER () AS DECIMAL(10,2)) AS median_price_ok
FROM dbo.dim_listing
WHERE price_flag = 'OK';

PRINT '=== Q2: by neighbourhood (neighbourhoods with 30+ listings) ===';
WITH base AS (
    SELECT neighbourhood, price, est_revenue_l365d, est_occupancy_nights_l365d, review_score_rating,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price)
               OVER (PARTITION BY neighbourhood) AS median_price
    FROM dbo.dim_listing
    WHERE price_flag = 'OK'
)
SELECT neighbourhood,
       COUNT(*)                                                         AS listings,
       CAST(MAX(median_price) AS DECIMAL(10,2))                         AS median_price,
       CAST(AVG(est_revenue_l365d) AS DECIMAL(12,0))                    AS avg_est_revenue,
       CAST(AVG(CAST(est_occupancy_nights_l365d AS FLOAT)) AS DECIMAL(6,1)) AS avg_nights_booked,
       CAST(AVG(review_score_rating) AS DECIMAL(4,2))                   AS avg_rating
FROM base
GROUP BY neighbourhood
HAVING COUNT(*) >= 30
ORDER BY listings DESC;

PRINT '=== Q3: room type x bedrooms ===';
WITH grp AS (
    SELECT room_type,
           CASE WHEN bedrooms IS NULL THEN 'Unknown'
                WHEN bedrooms <= 1    THEN '0-1'
                WHEN bedrooms = 2     THEN '2'
                WHEN bedrooms = 3     THEN '3'
                ELSE '4+' END AS bedroom_group,
           price, est_revenue_l365d
    FROM dbo.dim_listing
    WHERE price_flag = 'OK'
      AND room_type IN ('Entire home/apt', 'Private room')
), base AS (
    SELECT *, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price)
                  OVER (PARTITION BY room_type, bedroom_group) AS median_price
    FROM grp
)
SELECT room_type, bedroom_group,
       COUNT(*)                                       AS listings,
       CAST(MAX(median_price) AS DECIMAL(10,2))       AS median_price,
       CAST(AVG(est_revenue_l365d) AS DECIMAL(12,0))  AS avg_est_revenue
FROM base
GROUP BY room_type, bedroom_group
ORDER BY room_type, bedroom_group;

PRINT '=== Q4a: share of listing-days NOT available, by month (next 12 months) ===';
SELECT DATEFROMPARTS(YEAR(calendar_date), MONTH(calendar_date), 1) AS month_start,
       COUNT(DISTINCT calendar_date)                               AS days_in_data,
       CAST(100.0 * SUM(CASE WHEN is_available = 0 THEN 1 ELSE 0 END) / COUNT(*)
            AS DECIMAL(5,1))                                       AS pct_unavailable
FROM dbo.fact_calendar
GROUP BY DATEFROMPARTS(YEAR(calendar_date), MONTH(calendar_date), 1)
ORDER BY month_start;

PRINT '=== Q4b: New Year period, by day ===';
SELECT calendar_date,
       CAST(100.0 * SUM(CASE WHEN is_available = 0 THEN 1 ELSE 0 END) / COUNT(*)
            AS DECIMAL(5,1)) AS pct_unavailable
FROM dbo.fact_calendar
WHERE calendar_date BETWEEN '2026-12-20' AND '2027-01-05'
GROUP BY calendar_date
ORDER BY calendar_date;

PRINT '=== Q5a: reviews per year with year-over-year change ===';
WITH y AS (
    SELECT YEAR(review_date) AS review_year, COUNT(*) AS reviews
    FROM dbo.fact_review
    WHERE review_date >= '2016-01-01'
    GROUP BY YEAR(review_date)
)
SELECT review_year,
       reviews,
       CAST(100.0 * (reviews - LAG(reviews) OVER (ORDER BY review_year))
            / NULLIF(LAG(reviews) OVER (ORDER BY review_year), 0) AS DECIMAL(6,1)) AS yoy_pct
FROM y
ORDER BY review_year;

PRINT '=== Q5b: reviews by calendar month, full years 2023-2025 ===';
SELECT MONTH(review_date) AS month_no,
       COUNT(*)           AS reviews,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct_of_total
FROM dbo.fact_review
WHERE review_date >= '2023-01-01' AND review_date < '2026-01-01'
GROUP BY MONTH(review_date)
ORDER BY month_no;

PRINT '=== Q6: host type ===';
WITH base AS (
    SELECT host_type, price, est_revenue_l365d, est_occupancy_nights_l365d,
           review_score_rating, license_status,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price)
               OVER (PARTITION BY host_type) AS median_price
    FROM dbo.dim_listing
    WHERE price_flag = 'OK'
)
SELECT host_type,
       COUNT(*)                                                         AS listings,
       CAST(MAX(median_price) AS DECIMAL(10,2))                         AS median_price,
       CAST(AVG(CAST(est_occupancy_nights_l365d AS FLOAT)) AS DECIMAL(6,1)) AS avg_nights_booked,
       CAST(AVG(est_revenue_l365d) AS DECIMAL(12,0))                    AS avg_est_revenue,
       CAST(AVG(review_score_rating) AS DECIMAL(4,2))                   AS avg_rating,
       CAST(100.0 * SUM(CASE WHEN license_status = 'STRA registered' THEN 1 ELSE 0 END)
            / COUNT(*) AS DECIMAL(5,1))                                 AS pct_stra_registered
FROM base
GROUP BY host_type
ORDER BY listings DESC;
