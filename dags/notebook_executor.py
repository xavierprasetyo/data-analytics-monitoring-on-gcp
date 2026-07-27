"""
notebook_executor.py — Generic Notebook Execution DAG (Deferrable)

A reusable Composer DAG that executes BQ/Colab Enterprise notebooks,
solving 3 pain points with native BQ Scheduled Notebooks:
  1. No alerting → Covered by global failure listener + Composer alerts
  2. Hard to check logs → Output captured in Airflow UI via XCom
  3. Can't rerun with same params → Use Airflow "Clear task" to rerun

Notebooks are registered in dags/config/notebooks.yaml. Engineers add
entries there — no DAG code changes needed.

Architecture:
  - Uses Airflow's deferrable operator pattern (Airflow 2.2+)
  - Operator submits notebook execution job → defers to async trigger
  - Trigger polls Vertex AI operation in the triggerer process
  - Worker slot is FREE while notebook executes on Colab Enterprise
  - No zombie tasks, no blocked workers

Fault Injection:
  This DAG includes a chaos injection point before each notebook execution,
  controlled via Airflow Variables (chaos_enabled, chaos_error_rate).
"""

import json
import logging
import os
from datetime import timedelta
from pathlib import Path
from typing import Any

import yaml
from airflow import DAG
from airflow.exceptions import TaskDeferred
from airflow.models import BaseOperator
from airflow.operators.python import PythonOperator
from airflow.utils.dates import days_ago

from fault_injection import maybe_fail_task
from notebook_execution_trigger import NotebookExecutionTrigger

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
# Deferrable Notebook Execution Operator
# ---------------------------------------------------------------------------


class NotebookExecutionOperator(BaseOperator):
    """
    Deferrable operator that executes a notebook via Vertex AI.

    Phase 1 (execute): Submits the notebook execution job to Vertex AI,
    then defers to a trigger that polls the operation asynchronously.
    The worker slot is freed immediately.

    Phase 2 (execute_complete): Resumes when the trigger fires,
    processes the result, and pushes output to XCom.
    """

    template_fields = ("notebook_gcs_uri", "output_gcs_folder", "params")

    def __init__(
        self,
        notebook_gcs_uri: str,
        output_gcs_folder: str,
        params: dict | None = None,
        timeout_seconds: int = 3600,
        poll_interval: int = 30,
        **kwargs,
    ):
        super().__init__(**kwargs)
        self.notebook_gcs_uri = notebook_gcs_uri
        self.output_gcs_folder = output_gcs_folder
        self.params = params or {}
        self.timeout_seconds = timeout_seconds
        self.poll_interval = poll_interval

    def execute(self, context: dict) -> None:
        """
        Submit the notebook execution job and defer to the trigger.

        Uses the REST API directly to avoid the GAPIC client blocking
        on the LRO. The worker slot is freed in ~2 seconds.
        """
        import google.auth
        import google.auth.transport.requests
        import requests as http_requests

        project_id = os.environ.get(
            "GCP_PROJECT_ID",
            context["var"]["value"].get("project_id", ""),
        )
        region = os.environ.get("COMPOSER_LOCATION", "us-central1")

        log.info(
            "Submitting notebook execution: %s with params: %s",
            self.notebook_gcs_uri,
            json.dumps(self.params, indent=2),
        )

        runtime_template = os.environ.get(
            "NOTEBOOK_RUNTIME_TEMPLATE",
            f"projects/{project_id}/locations/{region}/notebookRuntimeTemplates/monitoring-lab-runtime-v2",
        )

        # Build the request body
        display_name = f"notebook-executor-{self.task_id}-{context['ts_nodash']}"

        # Use REST API directly — returns immediately with operation name
        credentials, _ = google.auth.default()
        auth_req = google.auth.transport.requests.Request()
        credentials.refresh(auth_req)

        # Derive the service account from the credentials
        svc_account = getattr(credentials, "service_account_email", None)
        if not svc_account or svc_account == "default":
            # Fall back to looking up via projects API
            proj_resp = http_requests.get(
                f"https://cloudresourcemanager.googleapis.com/v1/projects/{project_id}",
                headers={"Authorization": f"Bearer {credentials.token}"},
                timeout=10,
            )
            if proj_resp.status_code == 200:
                proj_num = proj_resp.json().get("projectNumber", "")
                svc_account = f"{proj_num}-compute@developer.gserviceaccount.com"

        body = {
            "display_name": display_name,
            "gcs_notebook_source": {
                "uri": self.notebook_gcs_uri,
            },
            "notebook_runtime_template_resource_name": runtime_template,
            "gcs_output_uri": self.output_gcs_folder,
            "execution_timeout": f"{self.timeout_seconds}s",
            "service_account": svc_account,
        }

        url = (
            f"https://{region}-aiplatform.googleapis.com/v1/"
            f"projects/{project_id}/locations/{region}/notebookExecutionJobs"
        )

        response = http_requests.post(
            url,
            json=body,
            headers={
                "Authorization": f"Bearer {credentials.token}",
                "Content-Type": "application/json",
            },
            timeout=30,  # HTTP timeout, not execution timeout
        )

        if response.status_code not in (200, 201):
            error_msg = f"Failed to create notebook execution job: {response.status_code} {response.text}"
            log.error(error_msg)
            raise RuntimeError(error_msg)

        operation_data = response.json()
        operation_name = operation_data.get("name", "")

        log.info(
            "Notebook execution job submitted (operation: %s). "
            "Deferring to trigger — worker slot is now FREE.",
            operation_name,
        )

        # Defer to the trigger — frees the worker slot immediately
        raise TaskDeferred(
            trigger=NotebookExecutionTrigger(
                operation_name=operation_name,
                project_id=project_id,
                region=region,
                poll_interval=self.poll_interval,
                timeout=self.timeout_seconds,
            ),
            method_name="execute_complete",
        )

    def execute_complete(self, context: dict, event: dict[str, Any]) -> str:
        """
        Handle the trigger event when the notebook execution completes.

        This method runs briefly on a worker to process the result.
        """
        status = event.get("status", "unknown")
        operation_name = event.get("operation_name", "unknown")

        if status == "success":
            output_uri = event.get("output_uri", "")
            job_name = event.get("job_name", "")

            log.info(
                "Notebook execution completed successfully. Output: %s, Job: %s",
                output_uri, job_name,
            )

            # Push to XCom for visibility in Airflow UI
            context["ti"].xcom_push(key="output_uri", value=output_uri)
            context["ti"].xcom_push(key="execution_job_name", value=job_name)

            return output_uri

        elif status == "timeout":
            error_msg = f"Notebook execution timed out: {event.get('message', '')}"
            log.error(error_msg)
            raise TimeoutError(error_msg)

        elif status == "failed":
            error_msg = (
                f"Notebook execution failed "
                f"(state={event.get('job_state', 'N/A')}): "
                f"{event.get('message', 'unknown error')}"
            )
            log.error(error_msg)
            raise RuntimeError(error_msg)

        else:
            error_msg = f"Unexpected trigger event status: {status} — {event}"
            log.error(error_msg)
            raise RuntimeError(error_msg)


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
        schedule="@hourly",
        start_date=days_ago(1),
        catchup=False,
        tags=["data-pipeline", "notebooks", "monitoring-lab"],
    ) as dag:
        for nb in notebooks:
            # Chaos — random failure before notebook execution
            chaos_task = PythonOperator(
                task_id=f"chaos_pre_{nb['name']}",
                python_callable=maybe_fail_task,
                op_kwargs={"label": f"notebook_executor.pre_{nb['name']}"},
            )

            # Execute the notebook via Vertex AI (DEFERRABLE)
            execute_task = NotebookExecutionOperator(
                task_id=f"run_{nb['name']}",
                notebook_gcs_uri=nb["gcs_uri"],
                output_gcs_folder=nb.get(
                    "output_folder",
                    "gs://{{ var.value.project_id }}-monitoring-lab-notebooks/outputs/",
                ),
                params=nb.get("params", {}),
                timeout_seconds=nb.get("timeout_seconds", 3600),
                poll_interval=30,
                retries=nb.get("retries", 1),
                retry_delay=timedelta(minutes=nb.get("retry_delay_min", 5)),
            )

            chaos_task >> execute_task
