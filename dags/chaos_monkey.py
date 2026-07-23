"""
chaos_monkey DAG — Intentionally creates failures to test monitoring alerts.

Runs every 30 minutes. Randomly:
  1. Fails tasks (50% chance) — triggers task failure alerts
  2. Runs heavy BQ queries — triggers slot-time alerts
  3. Logs errors — triggers log-based alerts
"""

import os
import random
from datetime import timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.bigquery import (
    BigQueryInsertJobOperator,
)
from airflow.utils.dates import days_ago

PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "da-monitoring-lab-07230757")
SILVER_DATASET = os.environ.get("BQ_DATASET_SILVER", "monitoring_lab_silver")

default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "retries": 0,  # No retries — we want failures to be visible
}

with DAG(
    dag_id="chaos_monkey",
    default_args=default_args,
    description="Intentionally creates failures to test monitoring and alerting",
    schedule_interval="*/30 * * * *",
    start_date=days_ago(1),
    catchup=False,
    tags=["testing", "chaos", "monitoring"],
) as dag:

    def random_failure(**context):
        """Fails ~50% of the time to trigger task failure alerts."""
        import logging
        logger = logging.getLogger("airflow.task")

        roll = random.random()
        if roll < 0.5:
            logger.error("CHAOS MONKEY: Intentional failure triggered! (roll=%.2f)", roll)
            raise Exception(
                f"Chaos Monkey intentional failure (roll={roll:.2f}). "
                "This tests DAG/task failure monitoring alerts."
            )
        else:
            logger.info("CHAOS MONKEY: Task survived this round (roll=%.2f)", roll)

    def log_error_spam(**context):
        """Generates ERROR log entries to trigger log-based alerts."""
        import logging
        logger = logging.getLogger("airflow.task")

        error_count = random.randint(1, 5)
        for i in range(error_count):
            logger.error(
                "CHAOS MONKEY ERROR #%d: Simulated error for monitoring alert testing. "
                "This is intentional and expected.", i + 1
            )
        logger.info("CHAOS MONKEY: Generated %d error log entries", error_count)

    # Task 1: Random failure (50% chance)
    maybe_fail = PythonOperator(
        task_id="maybe_fail",
        python_callable=random_failure,
    )

    # Task 2: Generate error logs
    generate_errors = PythonOperator(
        task_id="generate_error_logs",
        python_callable=log_error_spam,
    )

    # Task 3: Run an intentionally heavy query (triggers BQ slot-time alerts)
    heavy_query = BigQueryInsertJobOperator(
        task_id="heavy_query",
        configuration={
            "query": {
                "query": f"""
                -- Chaos Monkey: Intentionally cross-joins to consume slot time
                SELECT COUNT(*)
                FROM `{PROJECT_ID}.{SILVER_DATASET}.orders` a
                CROSS JOIN `{PROJECT_ID}.{SILVER_DATASET}.orders` b
                WHERE a.order_id != b.order_id
                LIMIT 1
                """,
                "useLegacySql": False,
            }
        },
    )

    # Run in parallel — each tests different alerting scenarios
    [maybe_fail, generate_errors, heavy_query]
