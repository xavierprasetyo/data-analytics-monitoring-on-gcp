# ---------------------------------------------------------------------------
# outputs.tf — Useful outputs after terraform apply
# ---------------------------------------------------------------------------

output "composer_airflow_uri" {
  description = "Airflow web UI URL"
  value       = google_composer_environment.lab.config[0].airflow_uri
}

output "composer_gcs_bucket" {
  description = "GCS bucket for Composer DAGs and data"
  value       = google_composer_environment.lab.config[0].dag_gcs_prefix
}

output "composer_env_name" {
  description = "Composer environment name"
  value       = google_composer_environment.lab.name
}

output "bq_dataset_id" {
  description = "BigQuery dataset ID"
  value       = google_bigquery_dataset.lab.dataset_id
}

output "pubsub_topic" {
  description = "Pub/Sub topic for alerts"
  value       = google_pubsub_topic.alerts.id
}

output "pubsub_debug_subscription" {
  description = "Pub/Sub subscription for debugging alerts"
  value       = google_pubsub_subscription.alerts_debug.id
}

output "notification_channel_email" {
  description = "Email notification channel ID"
  value       = google_monitoring_notification_channel.email.id
}

output "alerting_policies" {
  description = "List of all alerting policies created"
  value = {
    dag_run_failures    = google_monitoring_alert_policy.dag_run_failures.display_name
    task_failures       = google_monitoring_alert_policy.task_failures.display_name
    scheduler_heartbeat = google_monitoring_alert_policy.scheduler_heartbeat.display_name
    worker_evictions    = google_monitoring_alert_policy.worker_evictions.display_name
    database_health     = google_monitoring_alert_policy.database_health.display_name
    error_logs          = google_monitoring_alert_policy.error_logs.display_name
    dag_parse_errors    = google_monitoring_alert_policy.dag_parse_errors.display_name
  }
}

# ---------------------------------------------------------------------------
# Helper: deploy_dags command to copy-paste
# ---------------------------------------------------------------------------

output "deploy_dags_command" {
  description = "Run this command to deploy DAGs to Composer"
  value       = "bash scripts/deploy_dags.sh"
}
