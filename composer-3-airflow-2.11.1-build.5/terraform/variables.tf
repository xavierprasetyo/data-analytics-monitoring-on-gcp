# ---------------------------------------------------------------------------
# variables.tf — Input variables for the monitoring & alerting lab
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Composer and other resources"
  type        = string
  default     = "us-central1"
}

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

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
}

variable "bq_dataset_id" {
  description = "BigQuery dataset ID for the sample pipeline"
  type        = string
  default     = "monitoring_lab"
}

variable "bq_location" {
  description = "BigQuery dataset location"
  type        = string
  default     = "US"
}

variable "pubsub_topic_name" {
  description = "Pub/Sub topic name for alert forwarding"
  type        = string
  default     = "composer-alerts"
}

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
