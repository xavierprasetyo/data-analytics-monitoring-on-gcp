# ---------------------------------------------------------------------------
# monitoring_datastream.tf — Datastream alerting policies
#
# Conditional — only created when var.datastream_stream_ids is non-empty.
#
# Creates 4 alert policies:
#   1. Stream Throughput Stale (data stopped flowing)
#   2. Stream Unhealthy (error status)
#   3. Backfill Failures
#   4. High Replication Lag
# ---------------------------------------------------------------------------

locals {
  enable_datastream = length(var.datastream_stream_ids) > 0
}

# ---------------------------------------------------------------------------
# Log-based metric: Datastream Errors
#
# Captures error-level logs from Datastream streams.
# ---------------------------------------------------------------------------

resource "google_logging_metric" "datastream_errors" {
  count       = local.enable_datastream ? 1 : 0
  project     = var.project_id
  name        = "datastream_stream_errors"
  description = "Error-level logs from Datastream streams"

  filter = <<-EOT
    resource.type="datastream.googleapis.com/Stream"
    severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "stream_id"
      value_type  = "STRING"
      description = "The Datastream stream ID"
    }
  }

  label_extractors = {
    "stream_id" = "EXTRACT(resource.labels.stream_id)"
  }

  depends_on = [
    google_project_service.monitoring_apis,
  ]
}

# ---------------------------------------------------------------------------
# Log-based metric: Datastream Backfill Errors
# ---------------------------------------------------------------------------

resource "google_logging_metric" "datastream_backfill_errors" {
  count       = local.enable_datastream ? 1 : 0
  project     = var.project_id
  name        = "datastream_backfill_errors"
  description = "Backfill errors from Datastream streams"

  filter = <<-EOT
    resource.type="datastream.googleapis.com/Stream"
    severity>=ERROR
    textPayload=~"backfill|Backfill|BACKFILL"
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

# ---------------------------------------------------------------------------
# Policy 1: Stream Throughput Stale
#
# Fires when no events are received for 15 minutes, indicating the
# stream may be stuck or the source has stopped emitting changes.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "datastream_throughput_stale" {
  count        = local.enable_datastream ? 1 : 0
  project      = var.project_id
  display_name = "Datastream - Stream Throughput Stale"
  combiner     = "OR"
  enabled      = true
  severity     = "CRITICAL"

  documentation {
    content   = "No events received from Datastream for 15 minutes. The CDC stream may be stuck or the source database has stopped emitting changes. Check the Datastream console for stream status."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Datastream event count absent for 15 minutes"

    condition_absent {
      filter   = "resource.type = \"datastream.googleapis.com/Stream\" AND metric.type = \"datastream.googleapis.com/stream/event_count\""
      duration = "900s"

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
# Policy 2: Stream Unhealthy (error status)
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "datastream_unhealthy" {
  count        = local.enable_datastream ? 1 : 0
  project      = var.project_id
  display_name = "Datastream - Stream Unhealthy"
  combiner     = "OR"
  enabled      = true
  severity     = "CRITICAL"

  documentation {
    content   = "Datastream has logged errors indicating an unhealthy stream. Check the Datastream console and Cloud Logging for details."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Datastream error log count > 0"

    condition_threshold {
      filter          = "resource.type = \"datastream.googleapis.com/Stream\" AND metric.type = \"logging.googleapis.com/user/datastream_stream_errors\""
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
    auto_close = "3600s"
  }

  depends_on = [
    google_logging_metric.datastream_errors,
  ]
}

# ---------------------------------------------------------------------------
# Policy 3: Backfill Failures
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "datastream_backfill_failures" {
  count        = local.enable_datastream ? 1 : 0
  project      = var.project_id
  display_name = "Datastream - Backfill Failures"
  combiner     = "OR"
  enabled      = true
  severity     = "WARNING"

  documentation {
    content   = "Datastream backfill has encountered errors. This may result in incomplete historical data in BigQuery. Check Datastream console for backfill status."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Backfill error count > 0"

    condition_threshold {
      filter          = "resource.type = \"datastream.googleapis.com/Stream\" AND metric.type = \"logging.googleapis.com/user/datastream_backfill_errors\""
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
    auto_close = "3600s"
  }

  depends_on = [
    google_logging_metric.datastream_backfill_errors,
  ]
}

# ---------------------------------------------------------------------------
# Policy 4: High Replication Lag
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "datastream_high_lag" {
  count        = local.enable_datastream ? 1 : 0
  project      = var.project_id
  display_name = "Datastream - High Replication Lag"
  combiner     = "OR"
  enabled      = true
  severity     = "WARNING"

  documentation {
    content   = "Datastream replication lag exceeds ${var.datastream_lag_threshold_seconds} seconds. Data in BigQuery may be stale. Check source database load and Datastream throughput."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Replication lag > ${var.datastream_lag_threshold_seconds}s"

    condition_threshold {
      filter          = "resource.type = \"datastream.googleapis.com/Stream\" AND metric.type = \"datastream.googleapis.com/stream/total_latencies\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.datastream_lag_threshold_seconds
      duration        = "300s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "3600s"
  }
}
