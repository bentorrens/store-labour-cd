CREATE OR REPLACE TEMPORARY TABLE ADW_DEV.ADW_TEMP.TOTE AS (
SELECT 
STORE_CD
, PICK_SYSTEM_ONLINE_ORDER_NUM
, ITEM_CD
, UPPER(PICKED_ITEM_UOM_CD) AS UPCASE_PICKED_ITEM_UOM_CD
, PICKED_ITEM_QTY
, CASE WHEN UPCASE_PICKED_ITEM_UOM_CD='G' THEN 1 ELSE PICKED_ITEM_QTY END AS PICKED_ITEM_QTY_CLEAN -- weighted items item_qty displays their weight in grams, rather than the item quantity
, DISPATCH_UNIT_STATUS_NAME
, TROLLEY_ID
, TOTE_ID
, TROLLEY_PICK_START_TS
, TROLLEY_PICK_END_TS
, ITEM_PICK_TYPE_NAME
, DSPTCH_UNIT_STRG_TEMP_TYP_NAME
, ITEM_PICK_DT
, TRANSPORT_MODULE_TYPE_NAME
//Derived fields
, TROLLEY_ID||' '|| STORE_CD||' '||TROLLEY_PICK_END_TS AS UNIQUE_TROLLEY_ID -- distinct occasions when a trolley was used
, TOTE_ID||' '||STORE_CD||' '||TROLLEY_PICK_END_TS||' '||PICK_SYSTEM_ONLINE_ORDER_NUM AS UNIQUE_TOTE_ID -- distinct occasions when a tote was used
FROM ADW_PROD.ADW_STORE_OPS_PL.FACT_GOL_ORDER_TOTE_TRANSACTN 
WHERE 
    ITEM_PICK_DT BETWEEN '2020-04-19' AND '2020-04-26'
    AND DISPATCH_UNIT_STATUS_NAME='marshalled' --PL table only contains marshalled atm, however RDV contains more than just marshalled, to future proof the code we should be explicit on what to pull back (otherwise in the future we may end up with dupes)
    AND TROLLEY_ID IS NOT NULL 
  -- Some rows within Tote Feed haven’t actually been picked, therefore their trolley_id is null. 
  -- The reason why this would happen is that the pick had already occured but had been moved to a different tote (e.g. due to previous tote being too full, spillages etc).
  -- Note: When using Tote Feed we should be considering whether our business questions should include/ exclude this filter. Include filter-> Interested in picked onto a trolley only: Exclude filter -> Interested in condensed totes
);

//Items per Tote

CREATE OR REPLACE TEMPORARY TABLE ADW_DEV.ADW_TEMP.IPT AS (
SELECT
ITEM_PICK_DT
, STORE_CD
, DSPTCH_UNIT_STRG_TEMP_TYP_NAME
, TOTE_ID
, UNIQUE_TOTE_ID
, SUM(PICKED_ITEM_QTY_CLEAN) AS SUM_PICKED_ITEM_QTY_CLEAN
FROM ADW_DEV.ADW_TEMP.TOTE 
WHERE SUBSTR(TOTE_ID,1,2)!='AX' -- Frozen plastic bags. Normally we exclude these as you get a lot more than 8 per trolley
GROUP BY 1,2,3,4,5);

SELECT
ITEM_PICK_DT
, STORE_CD
, DSPTCH_UNIT_STRG_TEMP_TYP_NAME
, COUNT(DISTINCT TOTE_ID) AS UNIQUE_TOTES 
, COUNT(*) AS TOTAL_TOTES 
, SUM(SUM_PICKED_ITEM_QTY_CLEAN) AS SUM_PICKED_ITEM_QTY
, SUM(SUM_PICKED_ITEM_QTY_CLEAN)/COUNT(*) AS AVG_PICKED_ITEM_QTY_PER_TOTE
FROM ADW_DEV.ADW_TEMP.IPT
GROUP BY 1,2,3
ORDER BY 1,2,3;

//EXAMPLE: 

//Tote IDs which HAVE been reused [for different orders on the same date/store]: 

//... On 19th Apr / Store number 18 / Chilled temp class: There were 388 unique totes, which were used 398 times, with a picked item qty of 4,967 units (avg 12.5 units per tote)

//SELECT TOTE_ID, COUNT(DISTINCT UNIQUE_TOTE_ID)
//FROM ADW_DEV.ADW_TEMP.IPT 
//WHERE ITEM_PICK_DT='2020-04-19' AND STORE_CD=18 AND DSPTCH_UNIT_STRG_TEMP_TYP_NAME='chilled'
//GROUP BY 1
//HAVING COUNT(DISTINCT UNIQUE_TOTE_ID)>1
//ORDER BY 2 DESC;
//
//SELECT *
//FROM ADW_DEV.ADW_TEMP.TOTE 
//WHERE ITEM_PICK_DT='2020-04-19' AND STORE_CD=18 AND DSPTCH_UNIT_STRG_TEMP_TYP_NAME='chilled' AND TOTE_ID='AD0896'
//ORDER BY TROLLEY_PICK_START_TS, TROLLEY_PICK_END_TS;
//
//Totes per Trolley 

CREATE OR REPLACE TEMPORARY TABLE ADW_DEV.ADW_TEMP.TPT AS (
SELECT
ITEM_PICK_DT
, STORE_CD
, DSPTCH_UNIT_STRG_TEMP_TYP_NAME
, TROLLEY_ID
, TROLLEY_PICK_END_TS
, UNIQUE_TROLLEY_ID
, COUNT(DISTINCT TOTE_ID) AS CNT_TOTES -- Number of Totes in each Trolley Pick
, SUM(PICKED_ITEM_QTY_CLEAN) AS SUM_PICKED_ITEM_QTY_CLEAN -- Sum of total quantity of all items picked
FROM ADW_DEV.ADW_TEMP.TOTE 
WHERE SUBSTR(TOTE_ID,1,2)!='AX' -- Frozen plastic bags. Normally we exclude these as you get a lot more than 8 per trolley
GROUP BY 1,2,3,4,5,6
);

SELECT 
ITEM_PICK_DT
, STORE_CD
, DSPTCH_UNIT_STRG_TEMP_TYP_NAME
, COUNT(*) AS TROLLEY_CT
, SUM(CNT_TOTES) AS SUM_TOTES
, SUM(CNT_TOTES)/COUNT(*) AS AVG_TOTES_PER_TROLLEY
, SUM(SUM_PICKED_ITEM_QTY_CLEAN) AS SUM_PICKED_ITEM_QTY
, SUM(SUM_PICKED_ITEM_QTY_CLEAN)/COUNT(*) AS AVG_PICKED_ITEM_QTY_PER_TROLLEY
FROM ADW_DEV.ADW_TEMP.TPT
GROUP BY 1,2,3
ORDER BY 1,2,3;

//Lines per item 

SELECT
ITEM_PICK_DT
, STORE_CD
, DSPTCH_UNIT_STRG_TEMP_TYP_NAME
, ITEM_CD
, COUNT(*) AS PICK_LINES
, SUM(PICKED_ITEM_QTY_CLEAN) AS SUM_PICKED_ITEM_QTY
FROM ADW_DEV.ADW_TEMP.TOTE 
GROUP BY 1,2,3,4
ORDER BY 1,2,3,4;
-- Including totes with prefix AX because we are not interested in how many totes fit in trolleys here
//Total number of lines 

SELECT
ITEM_PICK_DT
, STORE_CD
, DSPTCH_UNIT_STRG_TEMP_TYP_NAME
, COUNT(*) AS PICK_LINES
, SUM(PICKED_ITEM_QTY_CLEAN) AS SUM_PICKED_ITEM_QTY
FROM ADW_DEV.ADW_TEMP.TOTE 
GROUP BY 1,2,3
ORDER BY 1,2,3;
-- Including totes with prefix AX because we are not interested in how many totes fit in trolleys here
