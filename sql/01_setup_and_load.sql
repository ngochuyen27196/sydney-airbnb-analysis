/* =====================================================================
   STEP 1 - Create database, staging tables, load the 3 CSV files
   Project: Sydney short-term rental market (Inside Airbnb, scrape 2026-09-17)
   Run in SSMS, one block at a time (select the block, press F5).
   Requires SQL Server 2017 or newer (BULK INSERT ... FORMAT = 'CSV').
   Put the 3 CSV files in C:\data\airbnb\ (or change the paths below):
       calendar.csv        (original file from Inside Airbnb)
       listings_slim.csv   (prepared file)
       reviews_slim.csv    (prepared file)
   ===================================================================== */

-- ---------- BLOCK 0: check your SQL Server version -------------------
SELECT @@VERSION AS sql_server_version;
GO

-- ---------- BLOCK 1: create the database and the staging schema ------
USE master;
GO
IF DB_ID('AirbnbSydney') IS NULL
    CREATE DATABASE AirbnbSydney;
GO
USE AirbnbSydney;
GO
IF SCHEMA_ID('stg') IS NULL
    EXEC('CREATE SCHEMA stg');
GO

-- ---------- BLOCK 2: create the staging tables -----------------------
-- Listings: every column is text on purpose. Cleaning and typing is Step 2.
DROP TABLE IF EXISTS stg.listings_raw;
CREATE TABLE stg.listings_raw (
    id                                          NVARCHAR(50),
    last_scraped                                NVARCHAR(50),
    host_id                                     NVARCHAR(50),
    host_since                                  NVARCHAR(50),
    host_is_superhost                           NVARCHAR(10),
    neighbourhood_cleansed                      NVARCHAR(100),
    latitude                                    NVARCHAR(50),
    longitude                                   NVARCHAR(50),
    property_type                               NVARCHAR(100),
    room_type                                   NVARCHAR(100),
    accommodates                                NVARCHAR(50),
    bedrooms                                    NVARCHAR(50),
    beds                                        NVARCHAR(50),
    price                                       NVARCHAR(50),
    minimum_nights                              NVARCHAR(50),
    maximum_nights                              NVARCHAR(50),
    has_availability                            NVARCHAR(10),
    availability_30                             NVARCHAR(50),
    availability_60                             NVARCHAR(50),
    availability_90                             NVARCHAR(50),
    availability_365                            NVARCHAR(50),
    number_of_reviews                           NVARCHAR(50),
    number_of_reviews_ltm                       NVARCHAR(50),
    number_of_reviews_l30d                      NVARCHAR(50),
    estimated_occupancy_l365d                   NVARCHAR(50),
    estimated_revenue_l365d                     NVARCHAR(50),
    first_review                                NVARCHAR(50),
    last_review                                 NVARCHAR(50),
    review_scores_rating                        NVARCHAR(50),
    review_scores_accuracy                      NVARCHAR(50),
    review_scores_cleanliness                   NVARCHAR(50),
    review_scores_checkin                       NVARCHAR(50),
    review_scores_communication                 NVARCHAR(50),
    review_scores_location                      NVARCHAR(50),
    review_scores_value                         NVARCHAR(50),
    license                                     NVARCHAR(500),
    instant_bookable                            NVARCHAR(10),
    calculated_host_listings_count              NVARCHAR(50),
    calculated_host_listings_count_entire_homes NVARCHAR(50),
    calculated_host_listings_count_private_rooms NVARCHAR(50),
    calculated_host_listings_count_shared_rooms NVARCHAR(50),
    reviews_per_month                           NVARCHAR(50)
);

-- Calendar: clean file, so typed columns are fine. NOTE: no price column.
DROP TABLE IF EXISTS stg.calendar_raw;
CREATE TABLE stg.calendar_raw (
    listing_id      BIGINT,
    [date]          DATE,
    available       CHAR(1),
    minimum_nights  INT,
    maximum_nights  INT
);

-- Reviews: comments were removed (230 MB of text we do not need).
-- id is NOT unique in the source (54 repeated ids), so no primary key here.
DROP TABLE IF EXISTS stg.reviews_raw;
CREATE TABLE stg.reviews_raw (
    listing_id  BIGINT,
    id          BIGINT,
    [date]      DATE
);
GO

-- ---------- BLOCK 3: load the files ----------------------------------
-- If you get "Cannot bulk load because the file could not be opened",
-- the SQL Server service cannot read that folder: move the files to
-- C:\data\airbnb\ and try again.

BULK INSERT stg.listings_raw
FROM 'C:\data\airbnb\listings_slim.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2,
      FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a',
      CODEPAGE = '65001', KEEPNULLS, TABLOCK);
GO

BULK INSERT stg.reviews_raw
FROM 'C:\data\airbnb\reviews_slim.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2,
      FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a',
      CODEPAGE = '65001', KEEPNULLS, TABLOCK);
GO

-- calendar.csv is ~7.6 million rows: takes about 1-3 minutes.
BULK INSERT stg.calendar_raw
FROM 'C:\data\airbnb\calendar.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2,
      FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a',
      CODEPAGE = '65001', KEEPNULLS, TABLOCK);
GO

-- ---------- BLOCK 4: checks (send me these results) ------------------
-- Check A: row counts
SELECT 'listings_raw' AS table_name, COUNT(*) AS row_count FROM stg.listings_raw
UNION ALL SELECT 'calendar_raw', COUNT(*) FROM stg.calendar_raw
UNION ALL SELECT 'reviews_raw',  COUNT(*) FROM stg.reviews_raw;

-- Check B: listings
SELECT COUNT(*)                                              AS listings,
       COUNT(DISTINCT id)                                    AS distinct_ids,
       COUNT(DISTINCT host_id)                               AS distinct_hosts,
       SUM(CASE WHEN price IS NULL OR price = '' THEN 1 ELSE 0 END) AS blank_price,
       MIN(last_scraped)                                     AS scraped_on
FROM stg.listings_raw;

-- Check C: calendar
SELECT MIN([date])                    AS first_date,
       MAX([date])                    AS last_date,
       COUNT(DISTINCT listing_id)     AS listings,
       SUM(CASE WHEN available = 'f' THEN 1 ELSE 0 END) AS rows_f,
       SUM(CASE WHEN available = 't' THEN 1 ELSE 0 END) AS rows_t
FROM stg.calendar_raw;

-- Check D: reviews
SELECT MIN([date]) AS first_review, MAX([date]) AS last_review,
       COUNT(DISTINCT listing_id) AS listings_with_reviews
FROM stg.reviews_raw;

-- Check E: look at a few raw rows
SELECT TOP 5 id, neighbourhood_cleansed, room_type, accommodates, bedrooms, price,
       estimated_occupancy_l365d, estimated_revenue_l365d, license
FROM stg.listings_raw;
