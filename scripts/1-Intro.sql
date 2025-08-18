/***************************************************************************************************       
Asset:        Zero to Snowflake - Getting Started with Snowflake
Version:      v1     
Copyright(c): 2025 Snowflake Inc. All rights reserved.
****************************************************************************************************

Getting Started with Snowflake
1. Virtual Warehouses & Settings
2. Using Persisted Query Results
3. Basic Data Transformation Techniques
4. Data Recovery with UNDROP
5. Resource Monitors
6. Budgets
7. Universal Search

****************************************************************************************************/

-- Before we start, run this query to set the session query tag.
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"zts","version":{"major":1, "minor":1},"attributes":{"is_quickstart":1, "source":"tastybytes", "vignette": "getting_started_with_snowflake"}}';

-- We'll begin by setting our Worksheet context. We will set our database, schema and role.

USE DATABASE zero_to_snowflake;
USE ROLE accountadmin;

/*   1. Virtual Warehouses & Settings 

    Virtual Warehouses are the dynamic, scalable, and cost-effective computing power that lets you 
    perform analysis on your Snowflake data. Their purpose is to handle all your data processing needs 
    without you having to worry about the underlying technical details.
*/

-- Let's first look at the warehouses that already exist on our account that you have access privileges for
SHOW WAREHOUSES;

-- You can easily create a warehouse with a simple SQL command
CREATE OR REPLACE WAREHOUSE my_wh
    COMMENT = 'My TastyBytes warehouse'
    WAREHOUSE_TYPE = 'standard'
    WAREHOUSE_SIZE = 'xsmall'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    SCALING_POLICY = 'standard'
    AUTO_SUSPEND = 60
    INITIALLY_SUSPENDED = false
    AUTO_RESUME = true;
    
-- Use the warehouse
USE WAREHOUSE my_wh;

SELECT * FROM raw_pos.truck_details;

--Size the warehouse up with a simple SQL Command 
ALTER WAREHOUSE my_wh SET warehouse_size = 'XLarge';

--Let's now take a look at the sales per truck.
SELECT
    o.truck_brand_name,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(o.price) AS total_sales
FROM analytics.orders_v o
GROUP BY o.truck_brand_name
ORDER BY total_sales DESC;

/*  2. Basic Transformation Techniques

    Now that our warehouse is configured and running, the plan is to get an understanding of the distribution 
    of our trucks' manufacturers, however, this information is embedded in another column 'truck_build' that stores
    information about the year, make and model in a VARIANT data type. 
*/
SELECT truck_build FROM raw_pos.truck_details;

/*  Zero Copy Cloning
 
    Snowflake's powerful Zero Copy Cloning lets us create identical, fully functional and separate copies of database 
    objects instantly, without using any additional storage space. 

    We can use this to make a development environment which will allows us to make changes to the data structures without changing
    production objects.

*/

-- Create the truck_dev table as a Zero Copy clone of the truck table
CREATE OR REPLACE TABLE raw_pos.truck_dev CLONE raw_pos.truck_details;

-- Verify successful truck table clone into truck_dev 
SELECT TOP 15 * 
FROM raw_pos.truck_dev
ORDER BY truck_id;

ALTER TABLE raw_pos.truck_dev ADD COLUMN IF NOT EXISTS year NUMBER;
ALTER TABLE raw_pos.truck_dev ADD COLUMN IF NOT EXISTS make VARCHAR(255);
ALTER TABLE raw_pos.truck_dev ADD COLUMN IF NOT EXISTS model VARCHAR(255);

/*
    Now let's update the new columns with the data extracted from the truck_build column.
    We will use the colon (:) operator to access the value of each key in the truck_build 
    column, then set that value to its respective column.
*/
UPDATE raw_pos.truck_dev
SET 
    year = truck_build:year::NUMBER,
    make = truck_build:make::VARCHAR,
    model = truck_build:model::VARCHAR;

-- Verify the 3 columns were successfully added to the table and populated with the extracted data from truck_build
SELECT year, make, model FROM raw_pos.truck_dev;

-- Now we can count the different makes and get a sense of the distribution in our TastyBytes food truck fleet.
SELECT 
    make,
    COUNT(*) AS count
FROM raw_pos.truck_dev
GROUP BY make
ORDER BY make ASC;

/*
    After running the query above, we notice a problem in our dataset. Some trucks' makes are 'Ford' and some are 'Ford_',
    giving us two different counts for the same truck manufacturer.
*/

-- First we'll use UPDATE to change any occurrence of 'Ford_' to 'Ford'
UPDATE raw_pos.truck_dev
    SET make = 'Ford'
    WHERE make = 'Ford_';

-- Verify the make column has been successfully updated 
SELECT truck_id, make 
FROM raw_pos.truck_dev
ORDER BY truck_id;

/*
    The make column looks good now so let's SWAP the truck table with the truck_dev table
    This command atomically swaps the metadata and data between two tables, instantly promoting the truck_dev table 
    to become the new production truck table.
*/
ALTER TABLE raw_pos.truck_details SWAP WITH raw_pos.truck_dev; 

-- Run the query from before to get an accurate make count
SELECT 
    make,
    COUNT(*) AS count
FROM raw_pos.truck_details
GROUP BY
    make
ORDER BY count DESC;
/*
    The changes look great. We'll perform some cleanup on our dataset by first dropping the truck_build 
    column from the production database now that we have split that data into three separate columns.
    Then we can drop the truck_dev table since we no longer need it.
*/

-- We can drop the old truck build column with a simple ALTER TABLE ... DROP COLUMN command
ALTER TABLE raw_pos.truck_details DROP COLUMN truck_build;

-- Now we can drop the truck_dev table
DROP TABLE raw_pos.truck_details;

/*  3. Data Recovery with UNDROP
	
    Oh no! We accidentally dropped the production truck table. 😱

    Let's restore the production 'truck' table ASAP using UNDROP!
*/

-- Optional: run this query to verify the 'truck' table no longer exists
    -- Note: The error 'Table TRUCK does not exist or not authorized.' means the table was dropped.
DESCRIBE TABLE raw_pos.truck_details;

--Run UNDROP on the production 'truck' table to restore it to the exact state it was in before being dropped
UNDROP TABLE raw_pos.truck_details;

--Verify the table was successfully restored
SELECT * from raw_pos.truck_details;

-- Now drop the real truck_dev table
DROP TABLE raw_pos.truck_dev;


-------------------------------------------------------------------------
--RESET--
-------------------------------------------------------------------------
-- Drop created objects
DROP RESOURCE MONITOR IF EXISTS my_resource_monitor;
DROP TABLE IF EXISTS raw_pos.truck_dev;

-- Reset truck details
CREATE OR REPLACE TABLE raw_pos.truck_details
AS 
SELECT * EXCLUDE (year, make, model)
FROM raw_pos.truck;

DROP WAREHOUSE IF EXISTS my_wh;
-- Unset Query Tag
ALTER SESSION UNSET query_tag;