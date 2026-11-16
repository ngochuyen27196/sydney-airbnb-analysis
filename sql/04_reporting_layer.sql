/* =====================================================================
   STEP 4 - Reporting layer for Power BI (schema rpt)
   Power BI will read ONLY the objects in schema rpt:
     rpt.dim_listing          view   (one row per listing)
     rpt.dim_neighbourhood    view   (38 rows)
     rpt.dim_room_type        view   (4 rows)
     rpt.dim_host_type        view   (3 rows)
     rpt.agg_availability     table  (calendar summarised by day x neighbourhood x room type x host type)
     rpt.agg_reviews_monthly  table  (reviews summarised by month x neighbourhood x room type x host type)
   Why summarise: the raw calendar has 7.6 million rows. Power BI does not
   need that detail, and a small table makes the report fast.
   Run each block with F5, in order.
   ===================================================================== */
USE AirbnbSydney;
GO

IF SCHEMA_ID('rpt') IS NULL
    EXEC('CREATE SCHEMA rpt');
GO

/* ---------- BLOCK 1: dimension views ---------------------------------- */
CREATE OR ALTER VIEW rpt.dim_listing AS
SELECT
    listing_id,
    host_id,
    neighbourhood,
    room_type,
    property_type,
    host_type,
    license_status,
    is_superhost,
    latitude,
    longitude,
    accommodates,
    bedrooms,
    beds,
    CASE WHEN bedrooms IS NULL THEN 'Unknown'
         WHEN bedrooms <= 1    THEN '0-1'
         WHEN bedrooms = 2     THEN '2'
         WHEN bedrooms = 3     THEN '3'
         ELSE '4+' END                                AS bedroom_group,
    price,
    price_flag,
    CASE WHEN price_flag = 'OK' THEN price END        AS price_ok,
    est_occupancy_nights_l365d,
    est_revenue_l365d,
    CASE WHEN price_flag = 'OK' THEN est_revenue_l365d END AS est_revenue_ok,
    availability_30,
    availability_60,
    availability_90,
    availability_365,
    minimum_nights,
    number_of_reviews,
    number_of_reviews_ltm,
    review_score_rating,
    review_score_cleanliness,
    review_score_location,
    review_score_value,
    host_listings_count,
    first_review,
    last_review
FROM dbo.dim_listing;
GO

CREATE OR ALTER VIEW rpt.dim_neighbourhood AS
SELECT DISTINCT neighbourhood
FROM dbo.dim_listing
WHERE neighbourhood IS NOT NULL;
GO

CREATE OR ALTER VIEW rpt.dim_room_type AS
SELECT DISTINCT
    room_type,
    CASE room_type WHEN 'Entire home/apt' THEN 1
                   WHEN 'Private room'    THEN 2
                   WHEN 'Hotel room'      THEN 3
                   WHEN 'Shared room'     THEN 4 END AS sort_order
FROM dbo.dim_listing
WHERE room_type IS NOT NULL;
GO

CREATE OR ALTER VIEW rpt.dim_host_type AS
SELECT DISTINCT
    host_type,
    CASE host_type WHEN 'Single'            THEN 1
                   WHEN 'Small (2-5)'       THEN 2
                   WHEN 'Professional (6+)' THEN 3 END AS sort_order
FROM dbo.dim_listing
WHERE host_type IS NOT NULL;
GO

/* ---------- BLOCK 2: summarised availability (takes up to ~1 minute) --
   listing_days      = number of listing-days in the group
   unavailable_days  = listing-days that are NOT available (booked or blocked)
   In Power BI: Unavailability % = SUM(unavailable_days) / SUM(listing_days)
   ------------------------------------------------------------------- */
DROP TABLE IF EXISTS rpt.agg_availability;
GO

SELECT
    c.calendar_date,
    d.neighbourhood,
    d.room_type,
    d.host_type,
    COUNT(*)                                                  AS listing_days,
    SUM(CASE WHEN c.is_available = 0 THEN 1 ELSE 0 END)       AS unavailable_days
INTO rpt.agg_availability
FROM dbo.fact_calendar AS c
JOIN dbo.dim_listing   AS d ON d.listing_id = c.listing_id
GROUP BY c.calendar_date, d.neighbourhood, d.room_type, d.host_type;
GO

/* ---------- BLOCK 3: summarised reviews ------------------------------ */
DROP TABLE IF EXISTS rpt.agg_reviews_monthly;
GO

SELECT
    DATEFROMPARTS(YEAR(r.review_date), MONTH(r.review_date), 1) AS review_month,
    d.neighbourhood,
    d.room_type,
    d.host_type,
    COUNT(*)                                                    AS reviews
INTO rpt.agg_reviews_monthly
FROM dbo.fact_review AS r
JOIN dbo.dim_listing AS d ON d.listing_id = r.listing_id
GROUP BY DATEFROMPARTS(YEAR(r.review_date), MONTH(r.review_date), 1),
         d.neighbourhood, d.room_type, d.host_type;
GO

/* ---------- BLOCK 4: checks (send me these results) -------------------
   Check A expected: dim_listing 20833, dim_neighbourhood 38, dim_room_type 4,
                     dim_host_type 3, agg_availability 89790, agg_reviews_monthly 22857
   Check B expected: listing_days 7604045, unavailable_days 3958059, reviews 829163
   ------------------------------------------------------------------- */
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
