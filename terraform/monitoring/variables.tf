# ---------------------------------------------------------------------------
# variables.tf — Input variables for the reusable monitoring module
#
# Engineers using this module fill in their resource names and apply.
# All service-specific variables are optional — leave empty to skip.
# ---------------------------------------------------------------------------

# ---- Required ----

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
}

# ---- Composer ----

variable "composer_env_name" {
  description = "Name of the Cloud Composer environment to monitor"
  type        = string
}

# ---- Datastream (optional — leave empty to skip) ----

variable "datastream_stream_ids" {
  description = "List of Datastream stream IDs to monitor. Leave empty to skip Datastream alerts."
  type        = list(string)
  default     = []
}

variable "datastream_lag_threshold_seconds" {
  description = "Replication lag threshold in seconds before alerting (default: 30 minutes)"
  type        = number
  default     = 1800
}

# ---- BigQuery ----

variable "bq_monitored_datasets" {
  description = "List of BigQuery dataset IDs to monitor for data freshness. Leave empty to skip freshness alerts."
  type        = list(string)
  default     = []
}

variable "bq_slot_time_threshold" {
  description = "Slot-seconds threshold for high slot-time alert (default: 86400 = 1 slot-day)"
  type        = number
  default     = 86400
}

variable "bq_freshness_absent_duration" {
  description = "Duration before alerting on stale data (default: 1 hour)"
  type        = string
  default     = "3600s"
}

variable "bq_reports_dataset_id" {
  description = "BigQuery dataset ID for monitoring reports (slot-time audit, storage comparison)"
  type        = string
  default     = "monitoring_reports"
}

variable "bq_location" {
  description = "BigQuery dataset location for the reports dataset"
  type        = string
  default     = "US"
}

# ---- GCS (dashboard only — no alerts) ----

variable "gcs_monitored_buckets" {
  description = "List of GCS bucket names to show in the Cost & Storage dashboard. Leave empty to skip."
  type        = list(string)
  default     = []
}

# ---- Notifications ----

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for alert notifications. Leave empty to skip Slack setup."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_channel_name" {
  description = "Slack channel name where alerts will be posted (e.g., #data-alerts)"
  type        = string
  default     = "#data-alerts"
}
