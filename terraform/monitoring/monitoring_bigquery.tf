# ---------------------------------------------------------------------------
# monitoring_bigquery.tf — BigQuery alerting policies, log-based metrics,
#                          and scheduled queries for monitoring
#
# Creates:
#   Alert Policies:
#     1. High Slot-Time Jobs (real-time)
#     2. Scheduled Query Failures
#     3. Data Freshness Stale
#
#   Scheduled Queries:
#     - Daily slot-time audit (INFORMATION_SCHEMA.JOBS)
#     - Daily storage comparison (INFORMATION_SCHEMA.TABLE_STORAGE)
#
#   Supporting Resources:
#     - Reporting dataset + tables
#     - Log-based metric for scheduled query failures
# ---------------------------------------------------------------------------

# ===================================================================
# REPORTING DATASET & TABLES
# ===================================================================

resource "google_bigquery_dataset" "monitoring_reports" {
  dataset_id  = var.bq_reports_dataset_id
  project     = var.project_id
  location    = var.bq_location
  description = "Monitoring reports — slot-time audits, storage comparisons"

  delete_contents_on_destroy = true

  labels = {
    purpose = "monitoring"
  }

  depends_on = [
    google_project_service.monitoring_apis,
  ]
}

# ===================================================================
# LOG-BASED METRICS
# ===================================================================

resource "google_logging_metric" "bq_scheduled_query_failures" {
  project     = var.project_id
  name        = "bq_scheduled_query_failures"
  description = "Failed BigQuery scheduled queries (Data Transfer Service)"

  filter = <<-EOT
    resource.type="bigquery_resource"
    severity>=ERROR
    protoPayload.methodName=~"google.cloud.bigquery.datatransfer"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "transfer_config_name"
      value_type  = "STRING"
      description = "Name of the failed transfer config"
    }
  }

  label_extractors = {
    "transfer_config_name" = "REGEXP_EXTRACT(protoPayload.resourceName, \"transferConfigs/([^/]+)\")"
  }

  depends_on = [
    google_project_service.monitoring_apis,
  ]
}

# ===================================================================
# SCHEDULED QUERIES
# ===================================================================

# ---------------------------------------------------------------------------
# Scheduled Query: Daily Slot-Time Audit
#
# Scans INFORMATION_SCHEMA.JOBS for jobs exceeding the slot-time threshold
# and writes results to the reporting table for review.
# ---------------------------------------------------------------------------

resource "google_bigquery_data_transfer_config" "slot_time_report" {
  project                = var.project_id
  display_name           = "Daily Slot-Time Audit"
  location               = var.bq_location
  data_source_id         = "scheduled_query"
  schedule               = "every 24 hours"
  destination_dataset_id = google_bigquery_dataset.monitoring_reports.dataset_id
  service_account_name   = data.google_compute_default_service_account.default.email

  params = {
    query = <<-EOQ
      -- Daily slot-time audit: finds jobs exceeding ${var.bq_slot_time_threshold} slot-seconds
      SELECT
        job_id,
        project_id,
        user_email,
        job_type,
        state,
        creation_time,
        end_time,
        total_slot_ms / 1000 AS total_slot_seconds,
        total_bytes_processed,
        total_bytes_billed,
        query
      FROM
        `region-${lower(var.bq_location)}`.INFORMATION_SCHEMA.JOBS
      WHERE
        creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
        AND state = 'DONE'
        AND total_slot_ms / 1000 > ${var.bq_slot_time_threshold}
      ORDER BY
        total_slot_seconds DESC
    EOQ

    destination_table_name_template = "bq_slot_time_report"
    write_disposition               = "WRITE_TRUNCATE"
  }

  depends_on = [
    google_bigquery_dataset.monitoring_reports,
  ]
}

# ---------------------------------------------------------------------------
# Scheduled Query: Daily Storage Comparison (Logical vs Physical)
#
# Queries INFORMATION_SCHEMA.TABLE_STORAGE to compare logical and physical
# storage per dataset, helping decide which billing model to use.
# ---------------------------------------------------------------------------

resource "google_bigquery_data_transfer_config" "storage_comparison" {
  project                = var.project_id
  display_name           = "Daily Storage Billing Comparison"
  location               = var.bq_location
  data_source_id         = "scheduled_query"
  schedule               = "every 24 hours"
  destination_dataset_id = google_bigquery_dataset.monitoring_reports.dataset_id
  service_account_name   = data.google_compute_default_service_account.default.email

  params = {
    query = <<-EOQ
      -- Daily storage comparison: logical vs physical bytes per dataset
      SELECT
        CURRENT_TIMESTAMP() AS snapshot_time,
        table_schema AS dataset_id,
        COUNT(*) AS table_count,
        SUM(total_logical_bytes) AS total_logical_bytes,
        SUM(total_physical_bytes) AS total_physical_bytes,
        SAFE_DIVIDE(SUM(total_physical_bytes), SUM(total_logical_bytes)) AS compression_ratio,
        -- Storage pricing comparison (approximate, US multi-region)
        -- Logical: $0.02/GB/month, Physical: $0.04/GB/month
        SUM(total_logical_bytes) / POW(1024, 3) * 0.02 AS est_monthly_cost_logical,
        SUM(total_physical_bytes) / POW(1024, 3) * 0.04 AS est_monthly_cost_physical,
        CASE
          WHEN SUM(total_physical_bytes) / POW(1024, 3) * 0.04 < SUM(total_logical_bytes) / POW(1024, 3) * 0.02
          THEN 'PHYSICAL_CHEAPER'
          ELSE 'LOGICAL_CHEAPER'
        END AS recommended_billing_model
      FROM
        `region-${lower(var.bq_location)}`.INFORMATION_SCHEMA.TABLE_STORAGE
      GROUP BY
        table_schema
      ORDER BY
        total_logical_bytes DESC
    EOQ

    destination_table_name_template = "bq_storage_comparison"
    write_disposition               = "WRITE_TRUNCATE"
  }

  depends_on = [
    google_bigquery_dataset.monitoring_reports,
  ]
}

# ===================================================================
# ALERT POLICIES
# ===================================================================

# ---------------------------------------------------------------------------
# Policy 1: High Slot-Time Jobs (real-time)
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "bq_high_slot_time" {
  project      = var.project_id
  display_name = "BigQuery - High Slot-Time Jobs"
  combiner     = "OR"
  enabled      = true
  severity     = "WARNING"

  documentation {
    content   = "A BigQuery job has consumed more than ${var.bq_slot_time_threshold} slot-seconds. This may indicate an inefficient query or a data explosion. Review the daily slot-time report in the '${var.bq_reports_dataset_id}' dataset."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Job slot-seconds > ${var.bq_slot_time_threshold}"

    condition_threshold {
      filter          = "resource.type = \"bigquery_project\" AND metric.type = \"bigquery.googleapis.com/query/execution_times\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.bq_slot_time_threshold
      duration        = "0s"

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

# ---------------------------------------------------------------------------
# Policy 2: Scheduled Query Failures
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "bq_scheduled_query_failures" {
  project      = var.project_id
  display_name = "BigQuery - Scheduled Query Failures"
  combiner     = "OR"
  enabled      = true
  severity     = "CRITICAL"

  documentation {
    content   = <<-EOT
      ## Scheduled Query Failed

      A BigQuery scheduled query has failed in project **${var.project_id}**.

      **Investigate:**
      - [BigQuery Scheduled Queries](https://console.cloud.google.com/bigquery/scheduled-queries?project=${var.project_id})
      - [Cloud Logging](https://console.cloud.google.com/logs/query;query=resource.type%3D%22bigquery_resource%22%20severity%3E%3DERROR?project=${var.project_id})
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Scheduled query failure count > 0"

    condition_threshold {
      filter          = "resource.type = \"global\" AND metric.type = \"logging.googleapis.com/user/bq_scheduled_query_failures\""
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
    google_logging_metric.bq_scheduled_query_failures,
  ]
}

# ---------------------------------------------------------------------------
# Policy 3: Data Freshness Stale
#
# Only created when bq_monitored_datasets is non-empty.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "bq_data_freshness" {
  count        = length(var.bq_monitored_datasets) > 0 ? 1 : 0
  project      = var.project_id
  display_name = "BigQuery - Data Freshness Stale"
  combiner     = "OR"
  enabled      = true
  severity     = "WARNING"

  documentation {
    content   = "BigQuery tables in the monitored datasets have not been modified within the expected freshness window (${var.bq_freshness_absent_duration}). Data may be stale. Check upstream pipelines (Datastream, Composer DAGs)."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Table last modified time absent for ${var.bq_freshness_absent_duration}"

    condition_absent {
      filter   = "resource.type = \"bigquery_dataset\" AND metric.type = \"bigquery.googleapis.com/storage/uploaded_row_count\""
      duration = var.bq_freshness_absent_duration

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
