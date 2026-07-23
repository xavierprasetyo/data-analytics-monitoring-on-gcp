-- ---------------------------------------------------------------------------
-- validate_data.sql
--
-- Data quality check on the staging table.
-- This query is designed to FAIL if:
--   1. The staging table has zero rows (data load issue)
--   2. Critical columns contain NULL values beyond a threshold
--
-- Parameters (replaced by Airflow's BigQueryInsertJobOperator via Jinja):
--   {{ params.project_id }}  — Your GCP project ID
--   {{ params.dataset_id }}  — Target dataset (e.g., monitoring_lab)
-- ---------------------------------------------------------------------------

-- Check 1: Ensure rows exist
-- The ASSERT statement will cause the query to fail with an error if false.
ASSERT (
    SELECT COUNT(*) FROM `{{ params.project_id }}.{{ params.dataset_id }}.staging_stackoverflow_posts`
) > 0
AS 'Data validation failed: staging_stackoverflow_posts has 0 rows';

-- Check 2: Ensure critical columns are not excessively NULL
ASSERT (
    SELECT COUNTIF(title IS NULL) * 100.0 / COUNT(*)
    FROM `{{ params.project_id }}.{{ params.dataset_id }}.staging_stackoverflow_posts`
) < 5.0
AS 'Data validation failed: more than 5% of titles are NULL';

-- If all checks pass, return a success summary
SELECT
    'ALL CHECKS PASSED' AS status,
    COUNT(*) AS total_rows,
    COUNTIF(title IS NULL) AS null_titles,
    MIN(creation_date) AS earliest_record,
    MAX(creation_date) AS latest_record
FROM `{{ params.project_id }}.{{ params.dataset_id }}.staging_stackoverflow_posts`;
