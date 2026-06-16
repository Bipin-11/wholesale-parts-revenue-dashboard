-- ============================================================
-- Wholesale Parts Distributor — Revenue & Supplier Performance
-- Snowflake Views
-- Source data: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1
-- Schema: BI_REPORTING.TPCH_VIEWS
-- ============================================================

-- Setup: dedicated database/schema for reporting views
CREATE OR REPLACE DATABASE BI_REPORTING;
CREATE OR REPLACE SCHEMA BI_REPORTING.TPCH_VIEWS;
USE SCHEMA BI_REPORTING.TPCH_VIEWS;


-- ------------------------------------------------------------
-- DIM_CUSTOMER
-- Customer info with nation + region already joined in.
-- Used on Page 1 for region/nation revenue breakdowns
-- (region/nation here = customer's location).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW DIM_CUSTOMER AS
SELECT
    C.C_CUSTKEY      AS CUSTOMER_KEY,
    C.C_NAME         AS CUSTOMER_NAME,
    C.C_MKTSEGMENT   AS MARKET_SEGMENT,
    C.C_NATIONKEY    AS NATION_KEY,
    N.N_NAME         AS NATION_NAME,
    N.N_REGIONKEY    AS REGION_KEY,
    R.R_NAME         AS REGION_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N
    ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R
    ON N.N_REGIONKEY = R.R_REGIONKEY;


-- ------------------------------------------------------------
-- DIM_SUPPLIER
-- Supplier info with nation + region already joined in.
-- Used on Page 2 for region/nation revenue breakdowns
-- (region/nation here = supplier's location).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW DIM_SUPPLIER AS
SELECT
    S.S_SUPPKEY      AS SUPPLIER_KEY,
    S.S_NAME         AS SUPPLIER_NAME,
    S.S_NATIONKEY    AS NATION_KEY,
    N.N_NAME         AS NATION_NAME,
    N.N_REGIONKEY    AS REGION_KEY,
    R.R_NAME         AS REGION_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.SUPPLIER S
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N
    ON S.S_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R
    ON N.N_REGIONKEY = R.R_REGIONKEY;


-- ------------------------------------------------------------
-- DIM_PART
-- Product attributes. PART_TYPE is the key field used for the
-- "revenue by product type" analysis on Page 2.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW DIM_PART AS
SELECT
    P_PARTKEY    AS PART_KEY,
    P_NAME       AS PART_NAME,
    P_MFGR       AS MANUFACTURER,
    P_BRAND      AS BRAND,
    P_TYPE       AS PART_TYPE,
    P_SIZE       AS PART_SIZE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART;


-- ------------------------------------------------------------
-- FACT_LINEITEM
-- Core fact table. LINEITEM joined to ORDERS to bring in
-- ORDER_DATE and CUSTOMER_KEY onto the line-item grain.
-- Revenue is pre-calculated so DAX measures stay simple.
-- Return flag / line status get readable labels since the raw
-- single-letter codes aren't self-explanatory.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW FACT_LINEITEM AS
SELECT
    L.L_ORDERKEY                                  AS ORDER_KEY,
    L.L_LINENUMBER                                AS LINE_NUMBER,
    L.L_PARTKEY                                   AS PART_KEY,
    L.L_SUPPKEY                                   AS SUPPLIER_KEY,
    O.O_CUSTKEY                                   AS CUSTOMER_KEY,
    O.O_ORDERDATE                                 AS ORDER_DATE,
    L.L_QUANTITY                                  AS QUANTITY,
    L.L_EXTENDEDPRICE                             AS EXTENDED_PRICE,
    L.L_DISCOUNT                                  AS DISCOUNT,
    L.L_TAX                                       AS TAX,
    L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)        AS NET_REVENUE,
    L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT) * (1 + L.L_TAX) AS REVENUE_WITH_TAX,
    L.L_RETURNFLAG                                AS RETURN_FLAG,
    CASE L.L_RETURNFLAG
        WHEN 'R' THEN 'Returned'
        WHEN 'A' THEN 'Accepted (No Return)'
        WHEN 'N' THEN 'Not Applicable'
        ELSE L.L_RETURNFLAG
    END                                            AS RETURN_FLAG_LABEL,
    L.L_LINESTATUS                                AS LINE_STATUS,
    CASE L.L_LINESTATUS
        WHEN 'O' THEN 'Open'
        WHEN 'F' THEN 'Fulfilled'
        ELSE L.L_LINESTATUS
    END                                            AS LINE_STATUS_LABEL
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
    ON L.L_ORDERKEY = O.O_ORDERKEY;


-- ------------------------------------------------------------
-- DIM_DATE
-- Generated calendar spine, 1992-01-01 through 1998-12-31.
-- Covers the full FACT_LINEITEM ORDER_DATE range
-- (1992-01-01 to 1998-08-02) with a buffer for clean year
-- boundaries. Marked as the Date Table in Power BI for
-- time-intelligence functions (SAMEPERIODLASTYEAR, etc.).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW DIM_DATE AS
WITH DATE_SPINE AS (
    SELECT DATEADD(DAY, SEQ4(), '1992-01-01') AS DATE_VALUE
    FROM TABLE(GENERATOR(ROWCOUNT => 3000))
)
SELECT
    DATE_VALUE,
    YEAR(DATE_VALUE)                          AS YEAR,
    MONTH(DATE_VALUE)                         AS MONTH_NUM,
    MONTHNAME(DATE_VALUE)                     AS MONTH_NAME,
    'Q' || QUARTER(DATE_VALUE)                AS QUARTER,
    TO_CHAR(DATE_VALUE, 'YYYY-MM')            AS YEAR_MONTH,
    TO_CHAR(DATE_VALUE, 'YYYY') || '-Q' || QUARTER(DATE_VALUE) AS YEAR_QUARTER,
    DAYOFWEEK(DATE_VALUE)                     AS DAY_OF_WEEK_NUM,
    DAYNAME(DATE_VALUE)                       AS DAY_NAME,
    DAYOFMONTH(DATE_VALUE)                    AS DAY_OF_MONTH,
    DAYOFYEAR(DATE_VALUE)                     AS DAY_OF_YEAR
FROM DATE_SPINE
WHERE DATE_VALUE <= '1998-12-31';


-- ============================================================
-- Validation queries (run after creating the views above)
-- ============================================================

-- Row counts
SELECT COUNT(*) FROM FACT_LINEITEM;   -- ~6,001,215
SELECT COUNT(*) FROM DIM_DATE;        -- 2,557
SELECT COUNT(*) FROM DIM_CUSTOMER;    -- 150,000
SELECT COUNT(*) FROM DIM_SUPPLIER;    -- 10,000
SELECT COUNT(*) FROM DIM_PART;        -- 200,000

-- Date range + headline totals
SELECT
    MIN(ORDER_DATE) AS MIN_DATE,
    MAX(ORDER_DATE) AS MAX_DATE,
    SUM(NET_REVENUE) AS TOTAL_REVENUE,
    COUNT(DISTINCT ORDER_KEY) AS TOTAL_ORDERS
FROM FACT_LINEITEM;
-- MIN_DATE = 1992-01-01, MAX_DATE = 1998-08-02
-- TOTAL_REVENUE ~ 218,102,223,885
-- TOTAL_ORDERS = 1,500,000

-- Orphan / referential integrity check — all should return 0
SELECT
    (SELECT COUNT(*) FROM FACT_LINEITEM F
     LEFT JOIN DIM_PART P ON F.PART_KEY = P.PART_KEY
     WHERE P.PART_KEY IS NULL) AS ORPHAN_PARTS,
    (SELECT COUNT(*) FROM FACT_LINEITEM F
     LEFT JOIN DIM_SUPPLIER S ON F.SUPPLIER_KEY = S.SUPPLIER_KEY
     WHERE S.SUPPLIER_KEY IS NULL) AS ORPHAN_SUPPLIERS,
    (SELECT COUNT(*) FROM FACT_LINEITEM F
     LEFT JOIN DIM_CUSTOMER C ON F.CUSTOMER_KEY = C.CUSTOMER_KEY
     WHERE C.CUSTOMER_KEY IS NULL) AS ORPHAN_CUSTOMERS,
    (SELECT COUNT(*) FROM FACT_LINEITEM F
     LEFT JOIN DIM_DATE D ON F.ORDER_DATE = D.DATE_VALUE
     WHERE D.DATE_VALUE IS NULL) AS ORPHAN_DATES;
