# ---------------------------------------------------------------------------
# monitoring_composer.tf — Cloud Composer alerting policies & log-based metrics
#
# Consolidated from the original monitoring.tf and logging.tf.
# Contains 8 alert policies + 2 log-based metrics:
#
#   Alert Policies:
#     1. Failed DAG Runs
#     2. Failed Task Instances
#     3. Scheduler Heartbeat Missing
#     4. Worker Pod Evictions
#     5. Database Health Degraded
#     6. Error Logs Detected (with dag_id/task_id labels)
#     7. DAG Parse Errors
#     8. Webserver Health Degraded (NEW)
#
#   Log-based Metrics:
#     - composer_task_errors (with label extractors)
#     - composer_dag_parse_errors
#
# NOTE: Notebook execution failures run as Composer DAG tasks and are
# automatically covered by alert #6 via the global failure listener.
# ---------------------------------------------------------------------------

# ===================================================================
# LOG-BASED METRICS
# ===================================================================

# ---------------------------------------------------------------------------
# Log-based metric: Composer Task Errors
#
# Counts ERROR+ severity log entries from the Composer environment and
# extracts structured fields (dag_id, task_id) from the JSON payload
# emitted by the global listener plugin.
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

  label_extractors = {
    "dag_id"     = "REGEXP_EXTRACT(textPayload, \"dag_id.{3,6}([a-zA-Z0-9_.-]+)\")"
    "task_id"    = "REGEXP_EXTRACT(textPayload, \"task_id.{3,6}([a-zA-Z0-9_.-]+)\")"
    "alert_type" = "REGEXP_EXTRACT(textPayload, \"alert_type.{3,6}([A-Z_]+)\")"
  }

  depends_on = [
    google_project_service.monitoring_apis,
  ]
}

# ---------------------------------------------------------------------------
# Log-based metric: Composer DAG Parse Errors
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
    google_project_service.monitoring_apis,
  ]
}

# ===================================================================
# ALERT POLICIES
# ===================================================================

# ---------------------------------------------------------------------------
# Policy 1: Failed DAG Runs
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "dag_run_failures" {
  project      = var.project_id
  display_name = "Composer - Failed DAG Runs"
  combiner     = "OR"
  enabled      = true
  severity     = "CRITICAL"

  documentation {
    content   = "A DAG run has failed in Cloud Composer environment '${var.composer_env_name}'. Check the Airflow UI for details."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "DAG run count with state=failed > 0"

    condition_threshold {
      filter          = "resource.type = \"cloud_composer_workflow\" AND metric.type = \"composer.googleapis.com/workflow/run_count\" AND metric.labels.state = \"failed\""
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
}

# ---------------------------------------------------------------------------
# Policy 2: Failed Task Instances
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "task_failures" {
  project      = var.project_id
  display_name = "Composer - Failed Task Instances"
  combiner     = "OR"
  enabled      = true
  severity     = "CRITICAL"

  documentation {
    content   = "Task instances have failed in Cloud Composer environment '${var.composer_env_name}'. Check the Airflow UI for the failing task details."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Finished task instance count with state=failed > 0"

    condition_threshold {
      filter          = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/finished_task_instance_count\" AND metric.labels.state = \"failed\""
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
}

# ---------------------------------------------------------------------------
# Policy 3: Scheduler Heartbeat Missing
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "scheduler_heartbeat" {
  project      = var.project_id
  display_name = "Composer - Scheduler Heartbeat Missing"
  combiner     = "OR"
  enabled      = true
  severity     = "CRITICAL"

  documentation {
    content   = "The Airflow scheduler in Cloud Composer environment '${var.composer_env_name}' has stopped sending heartbeats. The scheduler may be down or unhealthy."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Scheduler heartbeat absent for 5 minutes"

    condition_absent {
      filter   = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/scheduler_heartbeat_count\""
      duration = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "3600s"
  }
}

# ---------------------------------------------------------------------------
# Policy 4: Worker Pod Evictions
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "worker_evictions" {
  project      = var.project_id
  display_name = "Composer - Worker Pod Evictions"
  combiner     = "OR"
  enabled      = true
  severity     = "WARNING"

  documentation {
    content   = "Worker pods are being evicted in Cloud Composer environment '${var.composer_env_name}'. This usually indicates resource pressure (memory/CPU). Consider scaling up worker resources."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Worker pod eviction count > 0"

    condition_threshold {
      filter          = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/worker/pod_eviction_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period   = "900s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "3600s"
  }
}

# ---------------------------------------------------------------------------
# Policy 5: Database Health Degraded
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "database_health" {
  project      = var.project_id
  display_name = "Composer - Database Health Degraded"
  combiner     = "OR"
  enabled      = true
  severity     = "WARNING"

  documentation {
    content   = "The metadata database for Cloud Composer environment '${var.composer_env_name}' is reporting unhealthy status. This can cause DAG processing failures and scheduler issues."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Database health is unhealthy"

    condition_threshold {
      filter          = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/database_health\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "300s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "3600s"
  }
}

# ---------------------------------------------------------------------------
# Policy 6: Error Logs Detected (with dag_id/task_id labels)
#
# This is the most useful alert — it tells you exactly which DAG and task
# failed, with the exception message. Also covers notebook execution
# failures (notebook_executor DAG tasks).
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "error_logs" {
  project      = var.project_id
  display_name = "Composer - Error Logs Detected"
  combiner     = "OR"
  enabled      = true
  severity     = "CRITICAL"

  documentation {
    content   = <<-EOT
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
    display_name = "Error log count > 0"

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
  ]
}

# ---------------------------------------------------------------------------
# Policy 7: DAG Parse Errors
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
  ]
}

# ---------------------------------------------------------------------------
# Policy 8: Webserver Health Degraded (NEW)
#
# Fires when the Airflow webserver reports unhealthy status.
# This can prevent engineers from accessing the Airflow UI.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "webserver_health" {
  project      = var.project_id
  display_name = "Composer - Webserver Health Degraded"
  combiner     = "OR"
  enabled      = true
  severity     = "CRITICAL"

  documentation {
    content   = "The webserver for Cloud Composer environment '${var.composer_env_name}' is reporting unhealthy status. Engineers may not be able to access the Airflow UI."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Webserver health is unhealthy"

    condition_threshold {
      filter          = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/web_server/health\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "300s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "3600s"
  }
}
