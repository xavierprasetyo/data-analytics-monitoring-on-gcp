# DAG version: 2026-05-22-v4 (fix notify_success context keys for Airflow 3)
"""
sample_elt_pipeline.py — Sample ELT pipeline for monitoring & alerting learning.

This DAG simulates a realistic data pipeline with multiple runtimes:
  1. extract_airbyte    — Simulates an Airbyte data sync (BashOperator)
  2. load_to_staging_bq — Loads data from BQ public dataset (BigQueryInsertJobOperator)
  3. run_dbt_transform  — Simulates a dbt run (BashOperator)
  4. validate_data_bq   — Runs data quality checks (BigQueryInsertJobOperator)
  5. notify_success     — Logs a success message (PythonOperator)

FAILURE TRIGGERS:
  Each simulated task reads an Airflow Variable to control success/failure.
  Toggle these in the Airflow UI (Admin > Variables) to test alerting:
    - force_fail_airbyte = "true"  → Airbyte extraction fails
    - force_fail_dbt     = "true"  → dbt transformation fails

  The BQ tasks use real queries that can also fail (e.g., missing table/dataset).

MONITORING (Airflow 3):
  - Every task has on_failure_callback → sends email + Pub/Sub alert
  - The DAG has on_failure_callback → sends DAG-level failure summary
  - SLA feature was removed in Airflow 3; use Deadline Alerts instead
  - execution_date was removed in Airflow 3; use logical_date instead
"""

import os
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.models import Variable
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.bigquery import (
    BigQueryInsertJobOperator,
)

from callbacks import (
    dag_failure_callback,
    task_failure_callback,
    task_success_callback,
)

# ---------------------------------------------------------------------------
# Configuration — UPDATE THESE for your environment
# ---------------------------------------------------------------------------
GCP_PROJECT_ID = Variable.get("gcp_project_id", default_var="YOUR_PROJECT_ID")
BQ_DATASET_ID = Variable.get("bq_dataset_id", default_var="monitoring_lab")
GCP_CONN_ID = "google_cloud_default"  # Default Composer connection

# Path to simulation scripts (uploaded alongside DAGs)
SCRIPTS_DIR = os.path.join(os.environ.get("DAGS_FOLDER", "/home/airflow/gcs/dags"), "scripts")
SQL_DIR = os.path.join(os.environ.get("DAGS_FOLDER", "/home/airflow/gcs/dags"), "sql")

# ---------------------------------------------------------------------------
# Default args — applied to every task
# ---------------------------------------------------------------------------
default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "email_on_failure": False,  # We use callbacks instead for richer alerts
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
    "on_failure_callback": task_failure_callback,
    "on_success_callback": task_success_callback,
    "execution_timeout": timedelta(minutes=30),
}

# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------
with DAG(
    dag_id="sample_elt_pipeline",
    description="Sample ELT pipeline for monitoring & alerting learning lab",
    default_args=default_args,
    start_date=datetime(2025, 1, 1),
    schedule="0 6 * * *",  # Daily at 6 AM UTC
    catchup=False,
    max_active_runs=1,
    on_failure_callback=dag_failure_callback,
    tags=["learning", "monitoring", "elt"],
) as dag:

    # -----------------------------------------------------------------
    # Task 1: Simulate Airbyte extraction
    # -----------------------------------------------------------------
    extract_airbyte = BashOperator(
        task_id="extract_airbyte",
        bash_command=f"bash {SCRIPTS_DIR}/simulate_airbyte_sync.sh ",
        env={
            "FORCE_FAIL": "{{ var.value.get('force_fail_airbyte', 'false') }}",
        },
        doc_md="""
        ### Airbyte Extraction
        Simulates syncing data from a source database.
        - **Force failure**: Set Airflow Variable `force_fail_airbyte` to `true`
        - **Runtime**: ~8 seconds (simulated)
        """,
    )

    # -----------------------------------------------------------------
    # Task 2: Load data to BigQuery staging table
    # -----------------------------------------------------------------

    # Read the SQL file content
    load_staging_sql = Path(f"{SQL_DIR}/load_staging.sql").read_text()

    load_to_staging_bq = BigQueryInsertJobOperator(
        task_id="load_to_staging_bq",
        configuration={
            "query": {
                "query": load_staging_sql,
                "useLegacySql": False,
            }
        },
        params={
            "project_id": GCP_PROJECT_ID,
            "dataset_id": BQ_DATASET_ID,
        },
        gcp_conn_id=GCP_CONN_ID,
        location="US",
        doc_md="""
        ### BigQuery Staging Load
        Loads sample data from the Stack Overflow public dataset.
        - **Source**: `bigquery-public-data.stackoverflow.posts_questions`
        - **Target**: `{project}.{dataset}.staging_stackoverflow_posts`
        - **Force failure**: Delete the target dataset or revoke BQ permissions
        """,
    )

    # -----------------------------------------------------------------
    # Task 3: Simulate dbt transformation
    # -----------------------------------------------------------------
    run_dbt_transform = BashOperator(
        task_id="run_dbt_transform",
        bash_command=f"bash {SCRIPTS_DIR}/simulate_dbt_run.sh ",
        env={
            "FORCE_FAIL": "{{ var.value.get('force_fail_dbt', 'false') }}",
        },
        doc_md="""
        ### dbt Transformation
        Simulates running dbt models for data transformation.
        - **Force failure**: Set Airflow Variable `force_fail_dbt` to `true`
        - **Runtime**: ~8 seconds (simulated)
        """,
    )

    # -----------------------------------------------------------------
    # Task 4: Validate data in BigQuery
    # -----------------------------------------------------------------

    validate_data_sql = Path(f"{SQL_DIR}/validate_data.sql").read_text()

    validate_data_bq = BigQueryInsertJobOperator(
        task_id="validate_data_bq",
        configuration={
            "query": {
                "query": validate_data_sql,
                "useLegacySql": False,
            }
        },
        params={
            "project_id": GCP_PROJECT_ID,
            "dataset_id": BQ_DATASET_ID,
        },
        gcp_conn_id=GCP_CONN_ID,
        location="US",
        doc_md="""
        ### Data Validation
        Runs ASSERT-based quality checks on the staging data.
        - **Check 1**: Table has > 0 rows
        - **Check 2**: < 5% NULL titles
        - **Check 3**: No stale records (> 30 days old)
        - **Force failure**: Drop the staging table before this task runs
        """,
    )

    # -----------------------------------------------------------------
    # Task 5: Notify success
    # -----------------------------------------------------------------
    def _notify_success(**context):
        """Log a success message when the full pipeline completes."""
        dag_id = context.get('dag', context.get('dag_run', None))
        if hasattr(dag_id, 'dag_id'):
            dag_id = dag_id.dag_id
        run_id = context.get('run_id', 'N/A')
        logical_date = context.get('logical_date', context.get('data_interval_start', 'N/A'))
        print("=" * 50)
        print(" ✅ Pipeline completed successfully!")
        print(f" DAG: {dag_id}")
        print(f" Run ID: {run_id}")
        print(f" Logical Date: {logical_date}")
        print("=" * 50)

    notify_success = PythonOperator(
        task_id="notify_success",
        python_callable=_notify_success,
        doc_md="""
        ### Success Notification
        Logs a success message. This task only runs if all upstream tasks succeed.
        """,
    )

    # -----------------------------------------------------------------
    # Task dependencies (linear pipeline)
    # -----------------------------------------------------------------
    extract_airbyte >> load_to_staging_bq >> run_dbt_transform >> validate_data_bq >> notify_success
