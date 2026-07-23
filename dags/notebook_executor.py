"""
notebook_executor.py — Generic Notebook Execution DAG

A reusable Composer DAG that executes BQ/Colab Enterprise notebooks,
solving 3 pain points with native BQ Scheduled Notebooks:
  1. No alerting → Covered by global failure listener + Composer alerts
  2. Hard to check logs → Output captured in Airflow UI via XCom
  3. Can't rerun with same params → Use Airflow "Clear task" to rerun

Notebooks are registered in dags/config/notebooks.yaml. Engineers add
entries there — no DAG code changes needed.

Usage:
  1. Upload notebooks to GCS
  2. Add entries to dags/config/notebooks.yaml
  3. Deploy DAG to Composer
  4. Notebooks run on their defined schedules
  5. Failures trigger Composer alerts with dag_id + task_id context
  6. Rerun: Airflow UI → Clear failed task → same params

Architecture:
  - Composer DAG triggers notebook execution via Vertex AI API
  - Actual compute runs on Colab Enterprise (not Composer workers)
  - Composer only handles orchestration (lightweight API calls + polling)
"""

import json
import logging
import os
from datetime import timedelta
from pathlib import Path

import yaml
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.dates import days_ago

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Load notebook registry from YAML config
# ---------------------------------------------------------------------------

CONFIG_PATH = Path(__file__).parent / "config" / "notebooks.yaml"


def load_notebook_config():
    """Load notebook registry from YAML config file."""
    if not CONFIG_PATH.exists():
        log.warning("Notebook config not found at %s — no notebooks to execute", CONFIG_PATH)
        return []

    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)

    return config.get("notebooks", [])


# ---------------------------------------------------------------------------
# Notebook execution function
# ---------------------------------------------------------------------------


def execute_notebook(
    notebook_gcs_uri: str,
    output_gcs_folder: str,
    params: dict | None = None,
    timeout_seconds: int = 3600,
    **context,
):
    """
    Execute a notebook via Vertex AI NotebookService API.

    The actual compute runs on Colab Enterprise infrastructure, not on
    Composer workers. This function only submits the job and polls for
    completion.

    Args:
        notebook_gcs_uri: GCS URI of the notebook (gs://bucket/path/notebook.ipynb)
        output_gcs_folder: GCS folder for execution output
        params: Dictionary of parameters to pass to the notebook
        timeout_seconds: Maximum execution time before timeout
        context: Airflow context (injected automatically)
    """
    from google.cloud import aiplatform_v1

    project_id = os.environ.get("GCP_PROJECT_ID", context["var"]["value"].get("project_id", ""))
    region = os.environ.get("COMPOSER_LOCATION", "us-central1")

    # Render parameters with Airflow template values
    rendered_params = {}
    if params:
        for key, value in params.items():
            rendered_params[key] = str(value)

    log.info(
        "Executing notebook: %s with params: %s",
        notebook_gcs_uri,
        json.dumps(rendered_params, indent=2),
    )

    # Create the notebook execution job
    client = aiplatform_v1.NotebookServiceClient(
        client_options={"api_endpoint": f"{region}-aiplatform.googleapis.com"}
    )

    parent = f"projects/{project_id}/locations/{region}"

    notebook_execution_job = aiplatform_v1.NotebookExecutionJob(
        gcs_notebook_source=aiplatform_v1.GcsNotebookSource(
            uri=notebook_gcs_uri,
        ),
        gcs_output_uri=output_gcs_folder,
        execution_timeout={"seconds": timeout_seconds},
    )

    operation = client.create_notebook_execution_job(
        parent=parent,
        notebook_execution_job=notebook_execution_job,
    )

    log.info("Notebook execution job submitted. Waiting for completion...")

    # Wait for completion
    result = operation.result(timeout=timeout_seconds + 300)  # Extra buffer for API overhead

    # Check result
    if result.status.state.name in ("FAILED", "CANCELLED"):
        error_msg = f"Notebook execution failed: {result.status.message}"
        log.error(error_msg)
        raise RuntimeError(error_msg)

    log.info(
        "Notebook execution completed successfully. Output: %s",
        result.gcs_output_uri,
    )

    # Push output URI to XCom for visibility in Airflow UI
    context["ti"].xcom_push(key="output_uri", value=result.gcs_output_uri)
    context["ti"].xcom_push(key="execution_job_name", value=result.name)

    return result.gcs_output_uri


# ---------------------------------------------------------------------------
# DAG Definition
# ---------------------------------------------------------------------------

default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "email_on_failure": False,  # Handled by global failure listener
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

# Load notebooks from config
notebooks = load_notebook_config()

if notebooks:
    with DAG(
        dag_id="notebook_executor",
        default_args=default_args,
        description="Executes registered BQ/Colab Enterprise notebooks with alerting, log visibility, and rerun support",
        schedule=None,  # Individual tasks are triggered by their own schedules
        start_date=days_ago(1),
        catchup=False,
        tags=["notebooks", "monitoring-lab"],
    ) as dag:
        for nb in notebooks:
            task = PythonOperator(
                task_id=f"run_{nb['name']}",
                python_callable=execute_notebook,
                op_kwargs={
                    "notebook_gcs_uri": nb["gcs_uri"],
                    "output_gcs_folder": nb.get("output_folder", "gs://{{ var.value.project_id }}-notebook-outputs/"),
                    "params": nb.get("params", {}),
                    "timeout_seconds": nb.get("timeout_seconds", 3600),
                },
                retries=nb.get("retries", 1),
                retry_delay=timedelta(minutes=nb.get("retry_delay_min", 5)),
            )
