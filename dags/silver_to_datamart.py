"""
silver_to_datamart DAG — Aggregates SILVER data into DATAMART tables.

Runs every hour. Creates/replaces:
  1. revenue_by_product — Revenue aggregation by product and region
  2. order_status_summary — Order status counts over time

Fault Injection:
  This DAG includes a chaos injection point controlled via Airflow Variables:
    - chaos_check: Randomly fails before aggregation queries
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

from fault_injection import maybe_fail_task

PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "da-monitoring-lab-07230757")
SILVER_DATASET = os.environ.get("BQ_DATASET_SILVER", "monitoring_lab_silver")
DATAMART_DATASET = "monitoring_lab_datamart"

default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="silver_to_datamart",
    default_args=default_args,
    description="Aggregate silver data into datamart tables for BI",
    schedule_interval="@hourly",
    start_date=days_ago(1),
    catchup=False,
    tags=["data-pipeline", "datamart", "aggregation"],
) as dag:

    # Revenue by product and region
    revenue_by_product = BigQueryInsertJobOperator(
        task_id="revenue_by_product",
        configuration={
            "query": {
                "query": f"""
                CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATAMART_DATASET}.revenue_by_product` AS
                SELECT
                    product,
                    region,
                    DATE(created_at) AS order_date,
                    COUNT(*) AS order_count,
                    SUM(quantity) AS total_quantity,
                    ROUND(SUM(total_price), 2) AS total_revenue,
                    ROUND(AVG(total_price), 2) AS avg_order_value,
                    MIN(created_at) AS first_order,
                    MAX(created_at) AS last_order
                FROM `{PROJECT_ID}.{SILVER_DATASET}.orders`
                WHERE status NOT IN ('cancelled')
                GROUP BY product, region, DATE(created_at)
                ORDER BY total_revenue DESC
                """,
                "useLegacySql": False,
            }
        },
    )

    # Order status summary
    order_status_summary = BigQueryInsertJobOperator(
        task_id="order_status_summary",
        configuration={
            "query": {
                "query": f"""
                CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATAMART_DATASET}.order_status_summary` AS
                SELECT
                    status,
                    region,
                    DATE(updated_at) AS status_date,
                    COUNT(*) AS order_count,
                    ROUND(SUM(total_price), 2) AS total_value,
                    ROUND(AVG(
                        TIMESTAMP_DIFF(updated_at, created_at, MINUTE)
                    ), 1) AS avg_processing_minutes
                FROM `{PROJECT_ID}.{SILVER_DATASET}.orders`
                GROUP BY status, region, DATE(updated_at)
                ORDER BY status_date DESC, order_count DESC
                """,
                "useLegacySql": False,
            }
        },
    )

    # Chaos — random failure before aggregation (simulates pipeline crash)
    chaos_check = PythonOperator(
        task_id="chaos_check",
        python_callable=maybe_fail_task,
        op_kwargs={"label": "silver_to_datamart.pre_aggregation"},
    )

    chaos_check >> [revenue_by_product, order_status_summary]
