/* =====================================================================
   STEP 4b - Replacement for BLOCK 2 and BLOCK 3 of 04_reporting_layer.sql
   Why: grouping 7.6 million rows by three long text columns made SQL Server
   Express ask for more memory than it has (wait type RESOURCE_SEMAPHORE).
   Fix: give each (neighbourhood, room type, host type) combination a small
   integer group_id, aggregate by that integer, then join the names back.

   BEFORE running: cancel the old query (red Cancel button in SSMS) and wait
   until it stops. Then run THIS WHOLE FILE at once (F5, nothing selected).
   You do NOT need to rerun the dimension views from Block 1.
   ===================================================================== */
USE AirbnbSydney;
GO

-- 1) Lookup of the combinations and mapping from listing to group
DROP TABLE IF EXISTS #grp;
DROP TABLE IF EXISTS #lg;

SELECT ROW_NUMBER() OVER (ORDER BY neighbourhood, room_type, host_type) AS group_id,
       neighbourhood, room_type, host_type
INTO #grp
FROM (SELECT DISTINCT neighbourhood, room_type, host_type
      FROM dbo.dim_listing) AS x;

SELECT d.listing_id, g.group_id
INTO #lg
FROM dbo.dim_listing AS d
JOIN #grp AS g
  ON g.neighbourhood = d.neighbourhood
 AND g.room_type     = d.room_type
 AND g.host_type     = d.host_type;

CREATE UNIQUE CLUSTERED INDEX IX_lg ON #lg (listing_id);

-- 2) Availability: aggregate with integer keys only (small memory need)
DROP TABLE IF EXISTS #avail;

SELECT c.calendar_date,
       lg.group_id,
       COUNT(*)                                             AS listing_days,
       SUM(CASE WHEN c.is_available = 0 THEN 1 ELSE 0 END)  AS unavailable_days
INTO #avail
FROM dbo.fact_calendar AS c
JOIN #lg AS lg ON lg.listing_id = c.listing_id
GROUP BY c.calendar_date, lg.group_id
OPTION (MAX_GRANT_PERCENT = 10);

DROP TABLE IF EXISTS rpt.agg_availability;

SELECT a.calendar_date, g.neighbourhood, g.room_type, g.host_type,
       a.listing_days, a.unavailable_days
INTO rpt.agg_availability
FROM #avail AS a
JOIN #grp   AS g ON g.group_id = a.group_id;

-- 3) Reviews per month, same technique
DROP TABLE IF EXISTS #rev;

SELECT DATEFROMPARTS(YEAR(r.review_date), MONTH(r.review_date), 1) AS review_month,
       lg.group_id,
       COUNT(*) AS reviews
INTO #rev
FROM dbo.fact_review AS r
JOIN #lg AS lg ON lg.listing_id = r.listing_id
GROUP BY DATEFROMPARTS(YEAR(r.review_date), MONTH(r.review_date), 1), lg.group_id
OPTION (MAX_GRANT_PERCENT = 10);

DROP TABLE IF EXISTS rpt.agg_reviews_monthly;

SELECT v.review_month, g.neighbourhood, g.room_type, g.host_type, v.reviews
INTO rpt.agg_reviews_monthly
FROM #rev AS v
JOIN #grp AS g ON g.group_id = v.group_id;

-- 4) Checks (send me these results)
--    Check A expected: dim_listing 20833, dim_neighbourhood 38, dim_room_type 4,
--                      dim_host_type 3, agg_availability 89790, agg_reviews_monthly 22857
--    Check B expected: listing_days 7604045, unavailable_days 3958059, reviews 829163
PRINT '=== Check A: row counts ===';
SELECT 'dim_listing' AS object_name, COUNT(*) AS row_count FROM rpt.dim_listing
UNION ALL SELECT 'dim_neighbourhood',   COUNT(*) FROM rpt.dim_neighbourhood
UNION ALL SELECT 'dim_room_type',       COUNT(*) FROM rpt.dim_room_type
UNION ALL SELECT 'dim_host_type',       COUNT(*) FROM rpt.dim_host_type
UNION ALL SELECT 'agg_availability',    COUNT(*) FROM rpt.agg_availability
UNION ALL SELECT 'agg_reviews_monthly', COUNT(*) FROM rpt.agg_reviews_monthly;

PRINT '=== Check B: totals ===';
SELECT (SELECT SUM(listing_days)     FROM rpt.agg_availability)    AS listing_days,
       (SELECT SUM(unavailable_days) FROM rpt.agg_availability)    AS unavailable_days,
       (SELECT SUM(reviews)          FROM rpt.agg_reviews_monthly) AS reviews;

PRINT '=== Check C: dimension values ===';
SELECT room_type AS value, sort_order FROM rpt.dim_room_type ORDER BY sort_order;
SELECT host_type AS value, sort_order FROM rpt.dim_host_type ORDER BY sort_order;
