# ---------------------------------------------------------------------------
# outputs.tf — Simulation lab outputs
#
# Outputs resource names/IDs that the monitoring module needs.
# After `terraform apply`, copy these values to monitoring/terraform.tfvars.
# ---------------------------------------------------------------------------

# ---- Composer ----

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

# ---- Cloud SQL ----

output "cloudsql_instance_name" {
  description = "Cloud SQL PostgreSQL instance name"
  value       = google_sql_database_instance.source_pg.name
}

output "cloudsql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = google_sql_database_instance.source_pg.private_ip_address
}

# ---- Datastream ----

output "datastream_stream_id" {
  description = "Datastream stream ID"
  value       = google_datastream_stream.lab.stream_id
}

# ---- BigQuery ----

output "bq_datasets" {
  description = "BigQuery dataset IDs"
  value = {
    raw      = google_bigquery_dataset.raw.dataset_id
    silver   = google_bigquery_dataset.silver.dataset_id
    datamart = google_bigquery_dataset.datamart.dataset_id
  }
}

# ---- GCS ----

output "gcs_datalake_bucket" {
  description = "GCS data lake bucket name"
  value       = google_storage_bucket.datalake.name
}

# ---- Pub/Sub ----

output "pubsub_topic" {
  description = "Pub/Sub topic for alerts"
  value       = google_pubsub_topic.alerts.id
}

output "pubsub_debug_subscription" {
  description = "Pub/Sub subscription for debugging alerts"
  value       = google_pubsub_subscription.alerts_debug.id
}

# ---------------------------------------------------------------------------
# Helper: Values to copy into the monitoring module's terraform.tfvars
# ---------------------------------------------------------------------------

output "monitoring_module_inputs" {
  description = "Copy these values into monitoring/terraform.tfvars"
  value       = <<-EOT

    # --- Paste into terraform/monitoring/terraform.tfvars ---
    project_id             = "${var.project_id}"
    region                 = "${var.region}"
    alert_email            = "${var.alert_email}"
    composer_env_name      = "${google_composer_environment.lab.name}"
    datastream_stream_ids  = ["${google_datastream_stream.lab.stream_id}"]
    bq_monitored_datasets  = ["${var.bq_dataset_raw}", "${var.bq_dataset_silver}"]
    gcs_monitored_buckets  = ["${google_storage_bucket.datalake.name}"]

  EOT
}

output "deploy_dags_command" {
  description = "Run this command to deploy DAGs to Composer"
  value       = "bash scripts/deploy_dags.sh"
}
