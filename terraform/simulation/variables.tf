# ---------------------------------------------------------------------------
# variables.tf — Input variables for the simulation lab environment
# ---------------------------------------------------------------------------

# ---- General ----

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

# ---- Cloud Composer ----

variable "composer_env_name" {
  description = "Name of the Cloud Composer environment"
  type        = string
  default     = "monitoring-lab-composer"
}

variable "composer_image_version" {
  description = "Cloud Composer image version (Composer 3 + Airflow 2.11.x)"
  type        = string
  default     = "composer-3-airflow-2.11.1-build.5"
}

variable "composer_environment_size" {
  description = "Size of the Composer environment: ENVIRONMENT_SIZE_SMALL, ENVIRONMENT_SIZE_MEDIUM, ENVIRONMENT_SIZE_LARGE"
  type        = string
  default     = "ENVIRONMENT_SIZE_SMALL"
}

# ---- BigQuery ----

variable "bq_dataset_raw" {
  description = "BigQuery dataset ID for the raw layer (Datastream destination)"
  type        = string
  default     = "monitoring_lab_raw"
}

variable "bq_dataset_silver" {
  description = "BigQuery dataset ID for the silver layer (transformed data)"
  type        = string
  default     = "monitoring_lab_silver"
}

variable "bq_dataset_datamart" {
  description = "BigQuery dataset ID for the datamart layer (aggregated for BI)"
  type        = string
  default     = "monitoring_lab_datamart"
}

variable "bq_location" {
  description = "BigQuery dataset location"
  type        = string
  default     = "US"
}

# ---- Cloud SQL PostgreSQL ----

variable "cloudsql_instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance (Datastream source)"
  type        = string
  default     = "monitoring-lab-source-pg"
}

variable "cloudsql_tier" {
  description = "Machine tier for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
}

variable "cloudsql_db_name" {
  description = "Database name in Cloud SQL"
  type        = string
  default     = "source_db"
}

variable "cloudsql_db_password" {
  description = "Password for the Datastream replication user"
  type        = string
  sensitive   = true
  default     = "change-me-in-tfvars"
}

# ---- Datastream ----

variable "datastream_stream_name" {
  description = "Name of the Datastream CDC stream"
  type        = string
  default     = "monitoring-lab-stream"
}

# ---- GCS ----

variable "gcs_datalake_suffix" {
  description = "Suffix for the data lake GCS bucket (full name: {project_id}-{suffix})"
  type        = string
  default     = "monitoring-lab-datalake"
}

# ---- Pub/Sub ----

variable "pubsub_topic_name" {
  description = "Pub/Sub topic name for alert forwarding"
  type        = string
  default     = "composer-alerts"
}

# ---- Notifications (used by simulation to verify alerting) ----

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for alert notifications. Leave empty to skip Slack setup."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_channel_name" {
  description = "Slack channel name where alerts will be posted"
  type        = string
  default     = "#data-alerts"
}
