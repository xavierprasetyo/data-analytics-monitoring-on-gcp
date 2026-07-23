-- ---------------------------------------------------------------------------
-- load_staging.sql
--
-- Loads sample data from a BigQuery public dataset into a staging table.
-- Uses the Stack Overflow public dataset as sample data.
--
-- Parameters (replaced by Airflow's BigQueryInsertJobOperator via Jinja):
--   {{ params.project_id }}  — Your GCP project ID
--   {{ params.dataset_id }}  — Target dataset (e.g., monitoring_lab)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE `{{ params.project_id }}.{{ params.dataset_id }}.staging_stackoverflow_posts` AS
SELECT
    id,
    title,
    body,
    tags,
    creation_date,
    score,
    view_count,
    answer_count,
    favorite_count,
    owner_user_id
FROM
    `bigquery-public-data.stackoverflow.posts_questions`
ORDER BY
    creation_date DESC
LIMIT 1000;
