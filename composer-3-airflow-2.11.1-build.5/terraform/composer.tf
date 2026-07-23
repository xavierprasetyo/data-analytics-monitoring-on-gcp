# ---------------------------------------------------------------------------
# composer.tf — Cloud Composer 3 (Managed Airflow 2.11.1) environment
#
# Composer 3 simplifies infrastructure management:
#   - No workloads_config needed (auto-managed scheduler, workers, web server)
#   - Simplified networking (no VPC/subnet required)
#   - Improved maintenance handling
#
# This environment runs Airflow 2.11.1 on the Composer 3 platform.
# Provisioning takes ~20-25 minutes.
# ---------------------------------------------------------------------------

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_composer_environment" "lab" {
  name    = var.composer_env_name
  region  = var.region
  project = var.project_id

  config {
    software_config {
      image_version = var.composer_image_version

      # Airflow configuration overrides
      airflow_config_overrides = {
        # Enable email alerts (using SendGrid or SMTP configured in Composer)
        "email-email_backend"              = "airflow.utils.email.send_email_smtp"
        "core-dags_are_paused_at_creation" = "true"
      }

      # Environment variables available to all tasks
      env_variables = {
        GCP_PROJECT_ID = var.project_id
        BQ_DATASET_ID  = var.bq_dataset_id
      }
    }

    # Composer 3 requires an explicit service account
    node_config {
      service_account = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
    }

    environment_size = var.composer_environment_size
  }

  labels = {
    purpose     = "monitoring-lab"
    environment = "learning"
  }

  depends_on = [
    google_project_service.apis,
  ]
}
