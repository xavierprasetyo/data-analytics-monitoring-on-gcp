"""
raw_to_silver DAG — Merges CDC data from RAW layer to SILVER layer.

Runs every 15 minutes. Performs:
  1. MERGE from raw orders into silver (deduplication by order_id)
  2. Logs row counts for monitoring

Fault Injection:
  This DAG includes two chaos injection points controlled via Airflow Variables:
    - chaos_pre_merge:  Injects delay before MERGE (simulates slow BigQuery)
    - chaos_post_merge: Randomly fails after MERGE (simulates post-processing crash)
  Set chaos_enabled=true and chaos_error_rate=0-100 to control.
"""

import os
from datetime import timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.bigquery import (
    BigQueryInsertJobOperator,
)
from airflow.utils.dates import days_ago

from fault_injection import maybe_delay_task, maybe_fail_task

PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "da-monitoring-lab-07230757")
RAW_DATASET = os.environ.get("BQ_DATASET_RAW", "monitoring_lab_raw")
SILVER_DATASET = os.environ.get("BQ_DATASET_SILVER", "monitoring_lab_silver")

default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
}

with DAG(
    dag_id="raw_to_silver",
    default_args=default_args,
    description="Merge CDC data from RAW to SILVER layer (dedup + clean)",
    schedule_interval="*/15 * * * *",
    start_date=days_ago(1),
    catchup=False,
    tags=["data-pipeline", "silver", "merge"],
) as dag:

    # Step 1: Ensure silver table exists
    create_silver_table = BigQueryInsertJobOperator(
        task_id="create_silver_table",
        configuration={
            "query": {
                "query": f"""
                CREATE TABLE IF NOT EXISTS `{PROJECT_ID}.{SILVER_DATASET}.orders` (
                    order_id INT64 NOT NULL,
                    customer_id INT64 NOT NULL,
                    product STRING NOT NULL,
                    quantity INT64 NOT NULL,
                    unit_price NUMERIC NOT NULL,
                    total_price NUMERIC NOT NULL,
                    status STRING NOT NULL,
                    region STRING NOT NULL,
                    created_at TIMESTAMP NOT NULL,
                    updated_at TIMESTAMP NOT NULL,
                    _ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
                    _source STRING DEFAULT 'datastream_cdc'
                )
                PARTITION BY DATE(created_at)
                CLUSTER BY region, status
                """,
                "useLegacySql": False,
            }
        },
    )

    # Step 2: MERGE from RAW into SILVER
    merge_raw_to_silver = BigQueryInsertJobOperator(
        task_id="merge_raw_to_silver",
        configuration={
            "query": {
                "query": f"""
                MERGE `{PROJECT_ID}.{SILVER_DATASET}.orders` AS silver
                USING (
                    SELECT
                        CAST(order_id AS INT64) AS order_id,
                        CAST(customer_id AS INT64) AS customer_id,
                        CAST(product AS STRING) AS product,
                        CAST(quantity AS INT64) AS quantity,
                        CAST(unit_price AS NUMERIC) AS unit_price,
                        CAST(total_price AS NUMERIC) AS total_price,
                        CAST(status AS STRING) AS status,
                        CAST(region AS STRING) AS region,
                        CAST(created_at AS TIMESTAMP) AS created_at,
                        CAST(updated_at AS TIMESTAMP) AS updated_at
                    FROM `{PROJECT_ID}.{RAW_DATASET}.public_orders`
                    QUALIFY ROW_NUMBER() OVER (
                        PARTITION BY order_id ORDER BY updated_at DESC
                    ) = 1
                ) AS raw
                ON silver.order_id = raw.order_id
                WHEN MATCHED AND raw.updated_at > silver.updated_at THEN
                    UPDATE SET
                        customer_id = raw.customer_id,
                        product = raw.product,
                        quantity = raw.quantity,
                        unit_price = raw.unit_price,
                        total_price = raw.total_price,
                        status = raw.status,
                        region = raw.region,
                        updated_at = raw.updated_at,
                        _ingested_at = CURRENT_TIMESTAMP()
                WHEN NOT MATCHED THEN
                    INSERT (order_id, customer_id, product, quantity, unit_price,
                            total_price, status, region, created_at, updated_at,
                            _ingested_at, _source)
                    VALUES (raw.order_id, raw.customer_id, raw.product, raw.quantity,
                            raw.unit_price, raw.total_price, raw.status, raw.region,
                            raw.created_at, raw.updated_at,
                            CURRENT_TIMESTAMP(), 'datastream_cdc')
                """,
                "useLegacySql": False,
            }
        },
    )

    # Step 3: Chaos — inject delay before merge (simulates slow BigQuery)
    chaos_pre_merge = PythonOperator(
        task_id="chaos_pre_merge",
        python_callable=maybe_delay_task,
        op_kwargs={"label": "raw_to_silver.pre_merge"},
    )

    # Step 4: Chaos — random failure after merge (simulates post-processing crash)
    chaos_post_merge = PythonOperator(
        task_id="chaos_post_merge",
        python_callable=maybe_fail_task,
        op_kwargs={"label": "raw_to_silver.post_merge"},
    )

    # Step 5: Log row count
    def log_silver_count(**context):
        from airflow.providers.google.cloud.hooks.bigquery import BigQueryHook
        hook = BigQueryHook(use_legacy_sql=False, location="US")
        result = hook.get_records(
            sql=f"SELECT COUNT(*) FROM `{PROJECT_ID}.{SILVER_DATASET}.orders`"
        )
        count = result[0][0] if result else 0
        context["ti"].xcom_push(key="silver_row_count", value=count)
        print(f"Silver layer row count: {count}")

    log_count = PythonOperator(
        task_id="log_silver_row_count",
        python_callable=log_silver_count,
    )

    create_silver_table >> chaos_pre_merge >> merge_raw_to_silver >> chaos_post_merge >> log_count
