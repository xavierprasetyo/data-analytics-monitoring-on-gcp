"""
Shared callback functions for DAG and task-level alerting.

These callbacks are attached to tasks and DAGs to provide immediate
notifications when something fails or succeeds.

ARCHITECTURE:
  Callbacks write structured logs at ERROR severity. Cloud Logging captures
  these logs, log-based metrics count them, and Cloud Monitoring alerting
  policies evaluate the metrics and push notifications to ALL configured
  channels (Email, Slack, Pub/Sub) from one centralized place.

  This means we do NOT push directly to Slack or email from Python code.
  Instead, we rely on Cloud Monitoring's notification channel routing.
  This gives us:
    - Single source of truth for notification routing
    - Consistent alerting across all layers (callbacks, infra, logs)
    - No secrets (webhook URLs) stored in Airflow Variables

NOTE: Airflow 2.11.1 still supports the SLA feature (sla, sla_miss_callback).
Use SLAs for task-level duration alerts, and Cloud Monitoring alerting
policies (see terraform/monitoring.tf) for infrastructure-level alerts.

COMPATIBILITY:
  - execution_date is deprecated in Airflow 2.11.1 → use logical_date
  - Both execution_date and logical_date are available in the context
  - This code uses logical_date as primary, execution_date as fallback
"""

import json
import logging
import os
from datetime import datetime, timezone

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
COMPOSER_ENV_URL = "https://console.cloud.google.com/composer/environments"


def _build_task_context(context: dict) -> dict:
    """Extract useful fields from the Airflow callback context.

    Airflow 2.11.1 compatibility:
      - 'execution_date' is deprecated but still available
      - 'logical_date' is the preferred replacement (available since 2.2)
      - We use logical_date as primary, execution_date as fallback
    """
    ti = context.get("task_instance")
    dag = context.get("dag")
    return {
        "dag_id": dag.dag_id if dag else "unknown",
        "task_id": ti.task_id if ti else "unknown",
        "execution_date": str(context.get("logical_date", context.get("execution_date", ""))),
        "run_id": str(context.get("run_id", "")),
        "try_number": ti.try_number if ti else 0,
        "max_tries": ti.max_tries if ti else 0,
        "log_url": ti.log_url if ti else "",
        "exception": str(context.get("exception", "")),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


# ---------------------------------------------------------------------------
# Task-level callbacks
# ---------------------------------------------------------------------------


def task_failure_callback(context: dict) -> None:
    """
    Called when any task fails.

    Writes a structured ERROR log that Cloud Logging captures. The log-based
    metric 'composer_task_errors' counts these, and the alerting policy
    'Composer - Error Logs Detected' fires notifications to all configured
    channels (Email, Slack, Pub/Sub).

    Attach this to tasks via:
        default_args = {'on_failure_callback': task_failure_callback}
    """
    alert = _build_task_context(context)

    # Structured log at ERROR severity — this is what Cloud Logging captures
    # and what drives the log-based metric + alerting policy.
    log.error(
        json.dumps({
            "alert_type": "TASK_FAILURE",
            "message": f"Task {alert['task_id']} in DAG {alert['dag_id']} failed",
            "dag_id": alert["dag_id"],
            "task_id": alert["task_id"],
            "run_id": alert["run_id"],
            "execution_date": alert["execution_date"],
            "try_number": alert["try_number"],
            "max_tries": alert["max_tries"],
            "exception": alert["exception"],
            "log_url": alert["log_url"],
            "timestamp": alert["timestamp"],
        })
    )


def task_success_callback(context: dict) -> None:
    """
    Called when a task succeeds. Logs the success for audit trail.

    Attach this to tasks via:
        default_args = {'on_success_callback': task_success_callback}
    """
    alert = _build_task_context(context)
    log.info(
        "Task %s in DAG %s completed successfully.",
        alert["task_id"],
        alert["dag_id"],
    )


# ---------------------------------------------------------------------------
# DAG-level callbacks
# ---------------------------------------------------------------------------


def dag_failure_callback(context: dict) -> None:
    """
    Called when the entire DAG run fails.

    Writes a structured ERROR log. Cloud Monitoring alerting policies
    pick this up and route to all notification channels.

    Attach this to the DAG via:
        dag = DAG(..., on_failure_callback=dag_failure_callback)
    """
    alert = _build_task_context(context)

    log.error(
        json.dumps({
            "alert_type": "DAG_FAILURE",
            "message": f"DAG {alert['dag_id']} run failed",
            "dag_id": alert["dag_id"],
            "run_id": alert["run_id"],
            "execution_date": alert["execution_date"],
            "exception": alert["exception"],
            "composer_console": COMPOSER_ENV_URL,
            "timestamp": alert["timestamp"],
        })
    )
