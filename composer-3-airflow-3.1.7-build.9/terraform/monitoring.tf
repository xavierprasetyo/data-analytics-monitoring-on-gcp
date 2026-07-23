# ---------------------------------------------------------------------------
# monitoring.tf — Cloud Monitoring notification channels & alerting policies
#
# Creates the following:
#   - Email notification channel
#   - Slack notification channel (via incoming webhook)
#   - 5 alerting policies for Composer infrastructure health
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Notification Channel: Email
# ---------------------------------------------------------------------------

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Composer Alerts - Email"
  type         = "email"
  description  = "Email notifications for Cloud Composer pipeline alerts"

  labels = {
    email_address = var.alert_email
  }
}

# ---------------------------------------------------------------------------
# Notification Channel: Slack (optional — skipped if webhook URL is empty)
#
# Setup:
#   1. Go to https://api.slack.com/messaging/webhooks
#   2. Create an Incoming Webhook for your workspace/channel
#   3. Set the URL in terraform.tfvars as slack_webhook_url
# ---------------------------------------------------------------------------

resource "google_monitoring_notification_channel" "slack" {
  count        = var.slack_webhook_url != "" ? 1 : 0
  project      = var.project_id
  display_name = "Composer Alerts - Slack"
  type         = "slack"
  description  = "Slack notifications for Cloud Composer pipeline alerts"

  labels = {
    channel_name = var.slack_channel_name
  }

  sensitive_labels {
    auth_token = var.slack_webhook_url
  }
}

# ---------------------------------------------------------------------------
# Local: convenience reference to Composer environment name for filter strings
# ---------------------------------------------------------------------------

locals {
  composer_env_filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\""
  notification_channels = concat(
    [google_monitoring_notification_channel.email.id],
    google_monitoring_notification_channel.slack[*].id,
  )
}

# ---------------------------------------------------------------------------
# Policy 1: Failed DAG Runs
#
# Fires when any DAG run transitions to "failed" state.
# This catches pipeline-level failures regardless of which task failed.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "dag_run_failures" {
  project      = var.project_id
  display_name = "Composer - Failed DAG Runs"
  combiner     = "OR"
  enabled      = true

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

  depends_on = [
    google_composer_environment.lab,
  ]
}

# ---------------------------------------------------------------------------
# Policy 2: Failed Task Instances
#
# Fires when individual task instances fail. More granular than DAG failures.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "task_failures" {
  project      = var.project_id
  display_name = "Composer - Failed Task Instances"
  combiner     = "OR"
  enabled      = true

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

  depends_on = [
    google_composer_environment.lab,
  ]
}

# ---------------------------------------------------------------------------
# Policy 3: Scheduler Heartbeat Missing
#
# Fires when the Airflow scheduler stops sending heartbeats.
# This indicates the scheduler is down or unresponsive.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "scheduler_heartbeat" {
  project      = var.project_id
  display_name = "Composer - Scheduler Heartbeat Missing"
  combiner     = "OR"
  enabled      = true

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

  depends_on = [
    google_composer_environment.lab,
  ]
}

# ---------------------------------------------------------------------------
# Policy 4: Worker Pod Evictions
#
# Fires when worker pods are evicted due to resource pressure.
# This usually means workers need more memory or CPU.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "worker_evictions" {
  project      = var.project_id
  display_name = "Composer - Worker Pod Evictions"
  combiner     = "OR"
  enabled      = true

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

  depends_on = [
    google_composer_environment.lab,
  ]
}

# ---------------------------------------------------------------------------
# Policy 5: Database Health Degraded
#
# Fires when the Airflow metadata database reports unhealthy status.
# This can cause DAG processing failures and scheduler issues.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "database_health" {
  project      = var.project_id
  display_name = "Composer - Database Health Degraded"
  combiner     = "OR"
  enabled      = true

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

  depends_on = [
    google_composer_environment.lab,
  ]
}
