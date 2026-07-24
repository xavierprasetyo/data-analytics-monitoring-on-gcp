"""
Fault Injection Plugin — Configurable chaos for production DAGs.

Provides functions that DAGs call at injection points to simulate real-world
failures: random exceptions, BigQuery slowness, and corrupted queries.

All behaviour is controlled via Airflow Variables at RUNTIME (not parse time):
  - chaos_enabled       (true/false, default: false)   Master kill switch
  - chaos_error_rate    (0–100, default: 30)            Probability % per injection point
  - chaos_delay_seconds (int, default: 120)             Sleep duration for delay injection

USAGE IN A DAG:
    from fault_injection import maybe_fail_task, maybe_delay_task

    chaos_step = PythonOperator(
        task_id="chaos_pre_merge",
        python_callable=maybe_delay_task,
        op_kwargs={"label": "pre_merge"},
    )
    previous_task >> chaos_step >> next_task

DEPLOYMENT:
    gcloud composer environments storage plugins import \\
      --environment=$COMPOSER_ENV_NAME --location=$COMPOSER_LOCATION \\
      --source=plugins/fault_injection.py

COMPATIBILITY:
    - Target: composer-3-airflow-2.11.1-build.5
    - Uses Airflow Variable.get() with default_var for safe fallback
"""

import logging
import random
import time

from airflow.exceptions import AirflowException
from airflow.models import Variable

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _get_chaos_config():
    """Read chaos configuration from Airflow Variables at runtime.

    Returns a dict with:
      enabled (bool): whether chaos is active
      error_rate (float): probability 0.0–1.0
      delay_seconds (int): seconds to sleep for delay injection
    """
    enabled = Variable.get("chaos_enabled", default_var="false").lower() == "true"
    error_rate = int(Variable.get("chaos_error_rate", default_var="30"))
    delay_seconds = int(Variable.get("chaos_delay_seconds", default_var="120"))

    # Clamp error_rate to 0–100
    error_rate = max(0, min(100, error_rate))

    return {
        "enabled": enabled,
        "error_rate": error_rate / 100.0,
        "delay_seconds": delay_seconds,
    }


def _should_inject(config):
    """Roll the dice against the configured error rate."""
    roll = random.random()
    hit = roll < config["error_rate"]
    log.info(
        "CHAOS: roll=%.2f, threshold=%.2f, hit=%s",
        roll, config["error_rate"], hit,
    )
    return hit


# ---------------------------------------------------------------------------
# Public injection functions — called by DAG tasks
# ---------------------------------------------------------------------------


def maybe_fail_task(label="unknown", **context):
    """Randomly raise an AirflowException to simulate a task failure.

    Args:
        label: Human-readable name for the injection point (for log clarity).
    """
    config = _get_chaos_config()
    if not config["enabled"]:
        log.info("CHAOS [%s]: Fault injection disabled — skipping.", label)
        return

    if _should_inject(config):
        log.error(
            "CHAOS [%s]: Injecting task failure! "
            "(error_rate=%d%%)",
            label, int(config["error_rate"] * 100),
        )
        raise AirflowException(
            f"Chaos fault injection [{label}]: Intentional task failure "
            f"(error_rate={int(config['error_rate'] * 100)}%). "
            f"Disable with: airflow variables set chaos_enabled false"
        )
    else:
        log.info("CHAOS [%s]: Task survived this round.", label)


def maybe_delay_task(label="unknown", **context):
    """Randomly sleep to simulate a slow upstream system (e.g., BigQuery).

    Args:
        label: Human-readable name for the injection point.
    """
    config = _get_chaos_config()
    if not config["enabled"]:
        log.info("CHAOS [%s]: Fault injection disabled — skipping delay.", label)
        return

    if _should_inject(config):
        delay = config["delay_seconds"]
        log.warning(
            "CHAOS [%s]: Injecting %ds delay to simulate slow processing! "
            "(error_rate=%d%%)",
            label, delay, int(config["error_rate"] * 100),
        )
        time.sleep(delay)
        log.warning("CHAOS [%s]: Delay complete (%ds).", label, delay)
    else:
        log.info("CHAOS [%s]: No delay injected this round.", label)


def maybe_corrupt_query(original_sql, label="unknown"):
    """Randomly return broken SQL to simulate a corrupted query.

    Args:
        original_sql: The valid SQL query string.
        label: Human-readable name for the injection point.

    Returns:
        The original SQL if no injection, or intentionally broken SQL.
    """
    config = _get_chaos_config()
    if not config["enabled"]:
        log.info("CHAOS [%s]: Fault injection disabled — returning original SQL.", label)
        return original_sql

    if _should_inject(config):
        log.error(
            "CHAOS [%s]: Corrupting SQL query! (error_rate=%d%%)",
            label, int(config["error_rate"] * 100),
        )
        return (
            f"-- CHAOS INJECTED: Original query corrupted for testing\n"
            f"SELECT ERROR('Chaos fault injection [{label}]: "
            f"Intentional SQL failure')"
        )
    else:
        log.info("CHAOS [%s]: SQL passed through uncorrupted.", label)
        return original_sql
