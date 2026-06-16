# Wholesale Parts Distributor — Revenue & Supplier Performance Dashboard

A Power BI dashboard built on the Snowflake `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` dataset, analyzing revenue trends, regional performance, and product/supplier insights for a wholesale parts distribution business.

This document covers how I approached the data model in Snowflake, why I structured it the way I did, the DAX measures I used, and a page-by-page breakdown of the report.

---

## 1. How I approached the data model

The instructions were clear about not just dumping all 8 tables into Power BI and letting it auto-detect relationships, so I spent the first chunk of time in Snowflake setting up a proper star schema before touching Power BI at all.

I created a separate database/schema for this (`BI_REPORTING.TPCH_VIEWS`) and built views on top of the raw TPCH tables. The idea was to do the joins and cleanup once in SQL so the Power BI side stays simple — one fact table and four dimension tables, nothing more.

### What I ended up with

| View | Built from | Rows (approx) | Notes |
|---|---|---|---|
| `FACT_LINEITEM` | LINEITEM joined to ORDERS | ~6 million | Main fact table — revenue, quantity, dates, all the keys |
| `DIM_DATE` | Generated date spine (1992–1998) | ~2,550 | Calendar table, marked as a Date table for time intelligence |
| `DIM_CUSTOMER` | CUSTOMER + NATION + REGION | 150,000 | Customer info with region/nation already joined in |
| `DIM_SUPPLIER` | SUPPLIER + NATION + REGION | 10,000 | Same idea but for suppliers |
| `DIM_PART` | PART | 200,000 | Mainly using PART_TYPE for the product breakdowns |

A few things worth calling out about these choices:

- I didn't bring NATION and REGION in as separate tables. Instead I joined them into `DIM_CUSTOMER` and `DIM_SUPPLIER` directly in the SQL. Both customer and supplier link back to nation/region, and importing NATION as its own table would connect to both — causing ambiguous relationship paths in Power BI (you can only have one active path). Denormalizing it into the two dimensions avoided that problem entirely.
- For revenue, I used the standard TPC-H definition: `extendedprice * (1 - discount)`. I calculated this as a column in the `FACT_LINEITEM` view itself so I wasn't repeating that formula in every DAX measure.
- For time intelligence, I went with the order date from ORDERS rather than ship date or receipt date from LINEITEM — it represents when the sale was actually booked, which felt like the right anchor for revenue trends.
- I dropped columns I knew I wouldn't use — comments, addresses, phone numbers, clerk names, ship instructions, etc. No point bringing those into a ~6 million row table.

### One thing worth flagging — "region/nation" doesn't mean one fixed thing

TPC-H doesn't have a concept of a "sales region" — revenue isn't tied to a single geography on its own. So I made a judgment call:

- On **Page 1**, revenue by region/nation is based on the **customer's** location — "where did this revenue come from."
- On **Page 2**, region/nation refers to the **supplier's** location — "where does our supply come from."

I added short notes directly on each page so this isn't ambiguous to anyone opening the report cold. This is a reasonable interpretation, but it's an assumption I made rather than something the data states directly, so I wanted to be upfront about it.

---

## 2. The SQL views

Everything below was run in Snowflake, in order, under `BI_REPORTING.TPCH_VIEWS`.

### Setup

```sql
CREATE OR REPLACE DATABASE BI_REPORTING;
CREATE OR REPLACE SCHEMA BI_REPORTING.TPCH_VIEWS;
USE SCHEMA BI_REPORTING.TPCH_VIEWS;
```

### DIM_CUSTOMER

```sql
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
```

### DIM_SUPPLIER

```sql
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
```

### DIM_PART

```sql
CREATE OR REPLACE VIEW DIM_PART AS
SELECT
    P_PARTKEY    AS PART_KEY,
    P_NAME       AS PART_NAME,
    P_MFGR       AS MANUFACTURER,
    P_BRAND      AS BRAND,
    P_TYPE       AS PART_TYPE,
    P_SIZE       AS PART_SIZE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART;
```

### FACT_LINEITEM

This is the big one. Joins LINEITEM to ORDERS so I get the order date and customer key on the same row as the line item details, and pre-calculates the revenue fields. I also added readable labels for the return flag and line status codes (R/A/N and O/F) since those single-letter codes don't mean much on their own — used these for a small table on Page 1.

```sql
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
    L.L_LINESTATUS                                AS LINE_STATUS,
   FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
    ON L.L_ORDERKEY = O.O_ORDERKEY;
```

`NET_REVENUE` is the field every revenue measure sums up. `REVENUE_WITH_TAX` is there as an extra in case it's useful, but I didn't end up using it anywhere specific.

### DIM_DATE

Couldn't find a built-in calendar table so I generated one. Covers 1992-01-01 through end of 1998, which covers the full range of order dates in the fact table (1992-01-01 to 1998-08-02) with a bit of buffer.

```sql
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
```

One small thing — I kept `MONTH_NUM` alongside `MONTH_NAME` because if you sort by month name alphabetically, April comes before January, which messes up any chart that's supposed to go Jan–Dec. I sorted `MONTH_NAME` by `MONTH_NUM` in Power BI to fix this.

### Checks I ran before moving to Power BI

Just to make sure I wasn't building on top of broken joins, I ran a quick check for orphaned rows (line items pointing to a part/supplier/customer/date that doesn't exist in the dimension tables). All four came back as 0, so the joins are clean.

```sql
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
-- all four returned 0
```

---

## 3. Power BI side — model setup

Connected to Snowflake in Import mode and brought in just the 5 views: `FACT_LINEITEM`, `DIM_CUSTOMER`, `DIM_SUPPLIER`, `DIM_PART`, and `DIM_DATE`. Didn't bring in `DIM_REGION` or `DIM_NATION` as separate tables since that info is already inside `DIM_CUSTOMER` and `DIM_SUPPLIER`.

### Relationships

All four relationships are dimension-to-fact, one-to-many, single direction:

- `DIM_DATE[DATE_VALUE]` → `FACT_LINEITEM[ORDER_DATE]`
- `DIM_CUSTOMER[CUSTOMER_KEY]` → `FACT_LINEITEM[CUSTOMER_KEY]`
- `DIM_SUPPLIER[SUPPLIER_KEY]` → `FACT_LINEITEM[SUPPLIER_KEY]`
- `DIM_PART[PART_KEY]` → `FACT_LINEITEM[PART_KEY]`

Marked `DIM_DATE` as the official date table (using `DATE_VALUE`) so the YoY measures work properly with `SAMEPERIODLASTYEAR`. Ends up as a standard star schema — one fact table in the middle, four dimensions around it, no dimension tables talking to each other.

### A couple of data type things I had to fix

- `ORDER_DATE` came through fine as a Date, but I double checked the revenue columns (`NET_REVENUE`, `EXTENDED_PRICE`, etc.) were set to Fixed Decimal rather than general decimal, to avoid weird rounding in the visuals.
- Set `DIM_DATE[YEAR]` to "Don't summarize" since Power BI defaults numeric columns to Sum, and summing year numbers makes no sense in a table.

---

## 4. DAX measures

Put everything in a separate `_Measures` table to keep things tidy. The ask was for measures beyond simple sums, so along with the basic KPIs I added year-over-year, percent of total, and a ranking measure.

### Basic KPIs

```dax
Total Revenue = SUM(FACT_LINEITEM[NET_REVENUE])

Total Orders = DISTINCTCOUNT(FACT_LINEITEM[ORDER_KEY])

Average Order Value = DIVIDE([Total Revenue], [Total Orders])
```

### Year over year

```dax
Revenue PY = CALCULATE([Total Revenue], SAMEPERIODLASTYEAR(DIM_DATE[DATE_VALUE]))

Revenue YoY % = DIVIDE([Total Revenue] - [Revenue PY], [Revenue PY])

Revenue YoY Change = [Total Revenue] - [Revenue PY]
```

These two get reused on both pages — they work no matter what's on the axis (region, product type, supplier, whatever) because `SAMEPERIODLASTYEAR` is just shifting the date context, not anything else.

### Percent of total

```dax
Revenue % of Total =
DIVIDE(
    [Total Revenue],
    CALCULATE([Total Revenue], ALL(DIM_CUSTOMER), ALL(DIM_SUPPLIER), ALL(DIM_PART), ALL(DIM_DATE))
)
```

This gives each row's share of the overall total revenue (not just the total within whatever's currently filtered) — used in the top customers and top nations tables.

### A couple of extras

```dax
Total Quantity = SUM(FACT_LINEITEM[QUANTITY])

Distinct Products Sold = DISTINCTCOUNT(FACT_LINEITEM[PART_KEY])

Distinct Suppliers = DISTINCTCOUNT(FACT_LINEITEM[SUPPLIER_KEY])
```

### Sanity check numbers

With no filters applied, here's what the report should show — useful as a quick check that nothing's broken:

| Measure | Value |
|---|---|
| Total Revenue | ~ $218.1B |
| Total Orders | 1,500,000 |
| Average Order Value | ~ $145,401 |
| Date range in the data | Jan 1992 – Aug 1998 (1998 is a partial year) |

---

## 5. Page 1 — Revenue Overview

Note on this page: region/nation = customer's location, i.e. where the revenue is coming from.

| Visual | Type | What's on it |
|---|---|---|
| Total Revenue / Total Orders / Avg Order Value | KPI cards | `[Total Revenue]`, `[Total Orders]`, `[Average Order Value]` |
| Revenue trend | Line chart | X-axis = Month number, one line per Year (so you can compare Jan–Dec across years and see seasonality/YoY patterns at a glance) |
| Top 5 Nations by Revenue | Bar chart | `DIM_CUSTOMER[NATION_NAME]` (top 5) vs `[Total Revenue]` |
| Revenue by Region | Donut chart | `DIM_CUSTOMER[REGION_NAME]` vs `[Total Revenue]` |
| Filters | Slicers | Nation, Region, and Order Date (date range slider) |
| YoY Revenue Growth % | Line chart | `[Revenue YoY %]` by year — added a note that 1998 looks like a big drop only because it's a partial year |

---

## 6. Page 2 — Product & Supplier Performance

Note on this page: region/nation = supplier's location, i.e. where the parts are sourced from.

| Visual | Type | What's on it |
|---|---|---|
| Top 5 Product Types by Revenue | Bar chart | `DIM_PART[PART_TYPE]` (top 5) vs `[Total Revenue]` — the current snapshot of what's selling |
| Revenue Trend by Top 5 Product Types | Line chart | Same top 5 product types, by Year — shows how each one's trending over time |
| Top 10 Suppliers by Revenue | Bar chart | `DIM_SUPPLIER[SUPPLIER_NAME]` (top 10) vs `[Total Revenue]`, colored by Region so you can see geography at a glance |
| Filters / drill-down | Slicers | Part Type, Supplier Name, Region |
| Top 10 Supplier Nations by Revenue | Bar chart | `DIM_SUPPLIER[NATION_NAME]` (top 10) vs `[Total Revenue]` |

The reason I split product types into two visuals (bar chart + line chart) instead of one combined view: the bar chart answers "who's biggest right now" and the line chart answers "how has this changed over time" — trying to cram both into one visual (like a matrix) made it harder to read, so I kept them separate but using the same top 5.

---

## 7. A few other things

- Tested all the slicers — picking a region updates the KPIs, donut, bar charts and trend line correctly, and clearing filters brings everything back to the full totals (~$218.1B revenue, 1.5M orders).
- `DIM_REGION` and `DIM_NATION` views still exist in Snowflake from early on but aren't used in the final model — left them in just in case, they don't cause any issues sitting there unused.

That's pretty much it. Happy to walk through any of the decisions above in more detail.
