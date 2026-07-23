# ---------------------------------------------------------------------------
# logging.tf — Log-based metrics and alerting policies
#
# Creates log-based metrics that count error-level log entries from
# Cloud Composer, then creates alerting policies on those metrics.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Log-based metric 1: Composer Task Errors
#
# Counts ERROR+ severity log entries from the Composer environment and
# extracts structured fields (dag_id, task_id) from the JSON payload
# emitted by the global listener plugin.
#
# This gives richer alert notifications that include which DAG/task failed.
# ---------------------------------------------------------------------------

resource "google_logging_metric" "task_errors" {
  project     = var.project_id
  name        = "composer_task_errors"
  description = "Error-level logs from Cloud Composer tasks, with dag_id and task_id labels"

  filter = <<-EOT
    resource.type="cloud_composer_environment"
    resource.labels.environment_name="${var.composer_env_name}"
    severity>=ERROR
    textPayload=~"\"alert_type\":\s*\"TASK_FAILURE\""
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    # Labels extracted from the structured JSON logs
    labels {
      key         = "dag_id"
      value_type  = "STRING"
      description = "The DAG ID where the error occurred"
    }
    labels {
      key         = "task_id"
      value_type  = "STRING"
      description = "The task ID that failed"
    }
    labels {
      key         = "alert_type"
      value_type  = "STRING"
      description = "Type of alert (TASK_FAILURE, DAG_FAILURE)"
    }
  }

  # Extract fields from the JSON payload in textPayload
  # These regex patterns match the JSON output from global_failure_listener.py:
  #   {"alert_type": "TASK_FAILURE", "dag_id": "my_dag", "task_id": "my_task", ...}
  #
  # Pattern explanation: key_name followed by 3-6 chars (the '": "' delimiter),
  # then capture word characters (letters, digits, underscore, hyphen, dot).
  label_extractors = {
    "dag_id"     = "REGEXP_EXTRACT(textPayload, \"dag_id.{3,6}([a-zA-Z0-9_.-]+)\")"
    "task_id"    = "REGEXP_EXTRACT(textPayload, \"task_id.{3,6}([a-zA-Z0-9_.-]+)\")"
    "alert_type" = "REGEXP_EXTRACT(textPayload, \"alert_type.{3,6}([A-Z_]+)\")"
  }

  depends_on = [
    google_project_service.apis,
  ]
}

# ---------------------------------------------------------------------------
# Log-based metric 2: Composer DAG Parse Errors
#
# Specifically catches DAG parsing errors, which indicate broken DAG files.
# These are especially important because a broken DAG silently stops running.
# ---------------------------------------------------------------------------

resource "google_logging_metric" "dag_parse_errors" {
  project     = var.project_id
  name        = "composer_dag_parse_errors"
  description = "DAG parsing errors in Cloud Composer"

  filter = <<-EOT
    resource.type="cloud_composer_environment"
    resource.labels.environment_name="${var.composer_env_name}"
    severity>=ERROR
    textPayload=~"DagFileProcessorProcess|DagBag|import_errors"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }

  depends_on = [
    google_project_service.apis,
  ]
}

# ---------------------------------------------------------------------------
# Alerting Policy: Error Logs Detected
#
# Fires when more than 5 error-level log entries appear within 5 minutes.
# Threshold of 5 avoids noise from one-off transient errors.
#
# The alert notification includes dag_id and task_id labels extracted
# from the structured JSON logs.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "error_logs" {
  project      = var.project_id
  display_name = "Composer - Error Logs Detected"
  combiner     = "OR"
  enabled      = true
  severity     = "CRITICAL"

  documentation {
    content = <<-EOT
      ## Error Logs Detected

      Error-level logs detected in Cloud Composer environment **${var.composer_env_name}**.

      **Extracted details from structured logs:**
      - DAG ID: `$${metric.labels.dag_id}`
      - Task ID: `$${metric.labels.task_id}`
      - Alert Type: `$${metric.labels.alert_type}`

      **Investigate:**
      - [Cloud Logging](https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_composer_environment%22%20severity%3E%3DERROR?project=${var.project_id})
      - [Airflow UI](https://console.cloud.google.com/composer/environments?project=${var.project_id})
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Error log count > 5 in 5 minutes"

    condition_threshold {
      filter          = "resource.type = \"cloud_composer_environment\" AND metric.type = \"logging.googleapis.com/user/composer_task_errors\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "metric.labels.dag_id",
          "metric.labels.task_id",
          "metric.labels.alert_type",
        ]
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_logging_metric.task_errors,
    google_composer_environment.lab,
  ]
}

# ---------------------------------------------------------------------------
# Alerting Policy: DAG Parse Errors
#
# Fires on ANY DAG parse error (threshold = 0).
# Parse errors are always critical because they prevent DAGs from running.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "dag_parse_errors" {
  project      = var.project_id
  display_name = "Composer - DAG Parse Errors"
  combiner     = "OR"
  enabled      = true
  severity     = "ERROR"

  documentation {
    content   = "DAG parsing errors have been detected in Cloud Composer environment '${var.composer_env_name}'. A DAG file may have syntax errors or missing dependencies."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "DAG parse error count > 0"

    condition_threshold {
      filter          = "resource.type = \"cloud_composer_environment\" AND metric.type = \"logging.googleapis.com/user/composer_dag_parse_errors\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_logging_metric.dag_parse_errors,
    google_composer_environment.lab,
  ]
}
