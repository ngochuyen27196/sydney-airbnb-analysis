/* =====================================================================
   STEP 2 - Clean the raw data and build typed tables (schema dbo)
   Input : stg.listings_raw, stg.calendar_raw, stg.reviews_raw  (from Step 1)
   Output: dbo.dim_listing, dbo.fact_calendar, dbo.fact_review
   Run each block with F5, in order. The staging tables are NOT modified.
   ===================================================================== */

USE AirbnbSydney;
GO

/* ---------- BLOCK 1: dim_listing (one row per listing) ----------------
   Decisions made here (write them in your README later):
   1. Empty text becomes NULL. NULLIF(col,'') is needed because
      TRY_CAST('' AS INT) returns 0, not NULL.
   2. price '$1,234.50' -> DECIMAL(10,2). 3,112 listings have no price:
      we keep them (price = NULL), we do NOT invent a price.
   3. price >= 2000 per night is flagged, not deleted (price_flag).
   4. license is grouped into 4 statuses (license_status).
   5. host_type is based on calculated_host_listings_count.
   6. Columns that are 100% empty in this scrape (host_since,
      instant_bookable) are not carried over.
   ------------------------------------------------------------------- */
DROP TABLE IF EXISTS dbo.dim_listing;
GO

WITH typed AS (
    SELECT
        TRY_CAST(NULLIF(id, '') AS BIGINT)                          AS listing_id,
        TRY_CAST(NULLIF(host_id, '') AS BIGINT)                     AS host_id,
        CASE host_is_superhost WHEN 't' THEN CAST(1 AS BIT)
                               WHEN 'f' THEN CAST(0 AS BIT) END     AS is_superhost,
        NULLIF(neighbourhood_cleansed, '')                          AS neighbourhood,
        TRY_CAST(NULLIF(latitude, '')  AS DECIMAL(9,6))             AS latitude,
        TRY_CAST(NULLIF(longitude, '') AS DECIMAL(9,6))             AS longitude,
        NULLIF(property_type, '')                                   AS property_type,
        NULLIF(room_type, '')                                       AS room_type,
        TRY_CAST(NULLIF(accommodates, '') AS INT)                   AS accommodates,
        TRY_CAST(NULLIF(bedrooms, '') AS INT)                       AS bedrooms,
        TRY_CAST(NULLIF(beds, '') AS INT)                           AS beds,
        TRY_CAST(NULLIF(REPLACE(REPLACE(price, '$', ''), ',', ''), '')
                 AS DECIMAL(10,2))                                  AS price,
        TRY_CAST(NULLIF(minimum_nights, '') AS INT)                 AS minimum_nights,
        TRY_CAST(NULLIF(maximum_nights, '') AS INT)                 AS maximum_nights,
        TRY_CAST(NULLIF(availability_30, '')  AS INT)               AS availability_30,
        TRY_CAST(NULLIF(availability_60, '')  AS INT)               AS availability_60,
        TRY_CAST(NULLIF(availability_90, '')  AS INT)               AS availability_90,
        TRY_CAST(NULLIF(availability_365, '') AS INT)               AS availability_365,
        TRY_CAST(NULLIF(number_of_reviews, '')      AS INT)         AS number_of_reviews,
        TRY_CAST(NULLIF(number_of_reviews_ltm, '')  AS INT)         AS number_of_reviews_ltm,
        TRY_CAST(NULLIF(number_of_reviews_l30d, '') AS INT)         AS number_of_reviews_l30d,
        TRY_CAST(NULLIF(estimated_occupancy_l365d, '') AS INT)      AS est_occupancy_nights_l365d,
        TRY_CAST(NULLIF(estimated_revenue_l365d, '') AS DECIMAL(12,2)) AS est_revenue_l365d,
        TRY_CAST(NULLIF(first_review, '') AS DATE)                  AS first_review,
        TRY_CAST(NULLIF(last_review, '')  AS DATE)                  AS last_review,
        TRY_CAST(NULLIF(review_scores_rating, '')        AS DECIMAL(4,2)) AS review_score_rating,
        TRY_CAST(NULLIF(review_scores_accuracy, '')      AS DECIMAL(4,2)) AS review_score_accuracy,
        TRY_CAST(NULLIF(review_scores_cleanliness, '')   AS DECIMAL(4,2)) AS review_score_cleanliness,
        TRY_CAST(NULLIF(review_scores_checkin, '')       AS DECIMAL(4,2)) AS review_score_checkin,
        TRY_CAST(NULLIF(review_scores_communication, '') AS DECIMAL(4,2)) AS review_score_communication,
        TRY_CAST(NULLIF(review_scores_location, '')      AS DECIMAL(4,2)) AS review_score_location,
        TRY_CAST(NULLIF(review_scores_value, '')         AS DECIMAL(4,2)) AS review_score_value,
        NULLIF(license, '')                                         AS license_raw,
        TRY_CAST(NULLIF(calculated_host_listings_count, '') AS INT) AS host_listings_count,
        TRY_CAST(NULLIF(calculated_host_listings_count_entire_homes, '')  AS INT) AS host_entire_homes,
        TRY_CAST(NULLIF(calculated_host_listings_count_private_rooms, '') AS INT) AS host_private_rooms,
        TRY_CAST(NULLIF(calculated_host_listings_count_shared_rooms, '')  AS INT) AS host_shared_rooms,
        TRY_CAST(NULLIF(reviews_per_month, '') AS DECIMAL(6,2))     AS reviews_per_month
    FROM stg.listings_raw
)
SELECT
    t.*,
    CASE WHEN t.license_raw IS NULL             THEN 'Missing'
         WHEN t.license_raw = 'Exempt'          THEN 'Exempt'
         WHEN t.license_raw LIKE 'PID-STRA-%'   THEN 'STRA registered'
         ELSE 'Other' END                                           AS license_status,
    CASE WHEN t.host_listings_count = 1                   THEN 'Single'
         WHEN t.host_listings_count BETWEEN 2 AND 5       THEN 'Small (2-5)'
         WHEN t.host_listings_count >= 6                  THEN 'Professional (6+)'
         END                                                        AS host_type,
    CASE WHEN t.price IS NULL    THEN 'Missing'
         WHEN t.price >= 2000    THEN 'Outlier (>=2000)'
         ELSE 'OK' END                                              AS price_flag
INTO dbo.dim_listing
FROM typed AS t;
GO

ALTER TABLE dbo.dim_listing ALTER COLUMN listing_id BIGINT NOT NULL;
GO
ALTER TABLE dbo.dim_listing ADD CONSTRAINT PK_dim_listing PRIMARY KEY (listing_id);
GO

/* ---------- BLOCK 2: fact_calendar (one row per listing per day) ------
   available 't'/'f' becomes a BIT: 1 = available, 0 = NOT available.
   Remember: not available = booked OR blocked by the host.
   ------------------------------------------------------------------- */
DROP TABLE IF EXISTS dbo.fact_calendar;
GO

SELECT
    listing_id,
    [date]                                                  AS calendar_date,
    CASE available WHEN 't' THEN CAST(1 AS BIT)
                   ELSE CAST(0 AS BIT) END                  AS is_available,
    minimum_nights,
    maximum_nights
INTO dbo.fact_calendar
FROM stg.calendar_raw;
GO

CREATE CLUSTERED INDEX IX_fact_calendar
    ON dbo.fact_calendar (listing_id, calendar_date);
GO

/* ---------- BLOCK 3: fact_review (one row per review) -----------------
   review id is not unique in the source (54 repeated ids), so we keep
   all rows and do not create a primary key on it.
   ------------------------------------------------------------------- */
DROP TABLE IF EXISTS dbo.fact_review;
GO

SELECT
    listing_id,
    id          AS review_id,
    [date]      AS review_date
INTO dbo.fact_review
FROM stg.reviews_raw;
GO

CREATE CLUSTERED INDEX IX_fact_review
    ON dbo.fact_review (listing_id, review_date);
GO

/* ---------- BLOCK 4: checks (send me these results) -------------------
   Expected values are in the comment after each query.
   ------------------------------------------------------------------- */

-- Check A: row counts            expected: 20833 / 7604045 / 829163
SELECT 'dim_listing' AS table_name, COUNT(*) AS row_count FROM dbo.dim_listing
UNION ALL SELECT 'fact_calendar', COUNT(*) FROM dbo.fact_calendar
UNION ALL SELECT 'fact_review',   COUNT(*) FROM dbo.fact_review;

-- Check B: room types            expected: Entire home/apt 16445, Private room 4282,
--                                          Hotel room 58, Shared room 48
SELECT room_type, COUNT(*) AS listings
FROM dbo.dim_listing
GROUP BY room_type
ORDER BY listings DESC;

-- Check C: price                 expected: total 20833, null_price 3112,
--                                          outliers 448, min 16.90, max 96887.60
SELECT COUNT(*)                                             AS total,
       SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END)       AS null_price,
       SUM(CASE WHEN price_flag LIKE 'Outlier%' THEN 1 ELSE 0 END) AS outliers,
       MIN(price) AS min_price,
       MAX(price) AS max_price
FROM dbo.dim_listing;

-- Check D: license status        expected: STRA registered 15517, Exempt 4086, Missing 1230
SELECT license_status, COUNT(*) AS listings
FROM dbo.dim_listing
GROUP BY license_status
ORDER BY listings DESC;

-- Check E: host type             expected: Professional (6+) 8895, Single 7634, Small (2-5) 4304
SELECT host_type, COUNT(*) AS listings
FROM dbo.dim_listing
GROUP BY host_type
ORDER BY listings DESC;

-- Check F: NULLs and totals      expected: bedrooms_null 22, beds_null 308,
--                                          min_nights_null 13, rating_null 3210,
--                                          occ_min 0, occ_max 255, revenue_sum 487993130.00
SELECT SUM(CASE WHEN bedrooms IS NULL THEN 1 ELSE 0 END)            AS bedrooms_null,
       SUM(CASE WHEN beds IS NULL THEN 1 ELSE 0 END)                AS beds_null,
       SUM(CASE WHEN minimum_nights IS NULL THEN 1 ELSE 0 END)      AS min_nights_null,
       SUM(CASE WHEN review_score_rating IS NULL THEN 1 ELSE 0 END) AS rating_null,
       MIN(est_occupancy_nights_l365d)                              AS occ_min,
       MAX(est_occupancy_nights_l365d)                              AS occ_max,
       SUM(est_revenue_l365d)                                       AS revenue_sum
FROM dbo.dim_listing;

-- Check G: orphan rows           expected: 0 and 0
SELECT
  (SELECT COUNT(*) FROM dbo.fact_calendar c
   WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_listing d WHERE d.listing_id = c.listing_id)) AS calendar_orphans,
  (SELECT COUNT(*) FROM dbo.fact_review r
   WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_listing d WHERE d.listing_id = r.listing_id)) AS review_orphans;
