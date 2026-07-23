"""
Airflow 2.11.1 Listener Plugin — Global task failure alerting.

This listener automatically runs on EVERY task failure across ALL DAGs
without needing to add on_failure_callback to each DAG individually.

HOW IT WORKS:
  Airflow 2.6+ supports the Listener API (based on pluggy). You create a
  class with @hookimpl-decorated methods and register it via an AirflowPlugin.
  Airflow then calls these methods on every task lifecycle event.

DEPLOYMENT:
  Upload this file to the Composer plugins folder:
    gcloud composer environments storage plugins import \\
      --environment=YOUR_ENV --location=YOUR_LOCATION \\
      --source=plugins/global_failure_listener.py

  No DAG changes needed. No restarts needed. Composer picks it up
  automatically.

RELATIONSHIP TO on_failure_callback:
  - If a DAG already has on_failure_callback → BOTH fire (this listener
    AND the callback). The structured logs will have different sources
    but Cloud Monitoring deduplicates alerts via auto_close windows.
  - If a DAG does NOT have on_failure_callback → this listener still
    catches the failure.
  - Net effect: every task failure is captured, regardless of DAG config.

COMPATIBILITY:
  - Target: composer-3-airflow-2.11.1-build.5
  - Listener API available since Airflow 2.6
  - Import path: from airflow.listeners import hookimpl (same in 2.6+)
  - execution_date is deprecated → we include both execution_date and
    logical_date in the structured logs for maximum compatibility
"""

import json
import logging
from datetime import datetime, timezone

from airflow.listeners import hookimpl
from airflow.plugins_manager import AirflowPlugin

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Listener class — methods decorated with @hookimpl
# ---------------------------------------------------------------------------


class GlobalFailureListener:
    """Listens to task lifecycle events across ALL DAGs."""

    @hookimpl
    def on_task_instance_failed(self, previous_state, task_instance, error=None, session=None):
        """
        Called globally whenever ANY task instance fails in ANY DAG.

        Emits a structured ERROR log that Cloud Logging captures.
        The log-based metric 'composer_task_errors' counts these entries,
        and the alerting policy routes notifications to all channels
        (Email, Slack, Pub/Sub).
        """
        try:
            # Include both execution_date (deprecated) and logical_date for
            # compatibility across Airflow 2.x versions
            execution_date = ""
            if hasattr(task_instance, "logical_date") and task_instance.logical_date:
                execution_date = str(task_instance.logical_date)
            elif hasattr(task_instance, "execution_date") and task_instance.execution_date:
                execution_date = str(task_instance.execution_date)

            alert = {
                "alert_type": "TASK_FAILURE",
                "source": "global_listener",
                "message": f"Task {task_instance.task_id} in DAG {task_instance.dag_id} failed",
                "dag_id": task_instance.dag_id,
                "task_id": task_instance.task_id,
                "run_id": task_instance.run_id,
                "try_number": task_instance.try_number,
                "max_tries": task_instance.max_tries,
                "execution_date": execution_date,
                "log_url": task_instance.log_url if hasattr(task_instance, "log_url") else "",
                "exception": str(error) if error else "",
                "previous_state": str(previous_state),
                "operator": task_instance.operator if hasattr(task_instance, "operator") else "",
                "duration": str(task_instance.duration) if task_instance.duration else "",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }

            # This ERROR log is what drives Cloud Monitoring alerting
            log.error(json.dumps(alert))

        except Exception as e:
            # Never let the listener break the task lifecycle
            log.warning("Global failure listener error (non-fatal): %s", e)

    @hookimpl
    def on_task_instance_success(self, previous_state, task_instance, session=None):
        """
        Called globally whenever ANY task instance succeeds.
        Only logs at INFO level for audit trail — does not trigger alerts.
        """
        log.info(
            "Task %s in DAG %s succeeded (run_id=%s)",
            task_instance.task_id,
            task_instance.dag_id,
            task_instance.run_id,
        )


# ---------------------------------------------------------------------------
# Plugin registration — this is how Airflow discovers the listener
# ---------------------------------------------------------------------------


class GlobalFailureListenerPlugin(AirflowPlugin):
    """Registers the global failure listener with Airflow's plugin system."""
    name = "global_failure_listener"
    listeners = [GlobalFailureListener()]
