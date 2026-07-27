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
        "email-email_backend"              = "airflow.utils.email.send_email_smtp"
        "core-dags_are_paused_at_creation" = "true"
      }

      # Environment variables available to all tasks
      env_variables = {
        GCP_PROJECT_ID             = var.project_id
        BQ_DATASET_RAW             = var.bq_dataset_raw
        BQ_DATASET_SILVER          = var.bq_dataset_silver
        NOTEBOOKS_GCS_BUCKET       = "${var.project_id}-monitoring-lab-notebooks"
        NOTEBOOK_RUNTIME_TEMPLATE  = "projects/${var.project_id}/locations/${var.region}/notebookRuntimeTemplates/monitoring-lab-runtime"
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

# ---------------------------------------------------------------------------
# IAM — Grant the Composer service account BigQuery access
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "composer_bq_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "composer_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "composer_bq_resource_viewer" {
  project = var.project_id
  role    = "roles/bigquery.resourceViewer"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

# ---------------------------------------------------------------------------
# IAM — Grant the Composer service account Vertex AI notebook execution access
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "composer_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "composer_bq_read_session_user" {
  project = var.project_id
  role    = "roles/bigquery.readSessionUser"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_service_account_iam_member" "composer_sa_user" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_storage_bucket_iam_member" "composer_notebooks_storage" {
  bucket = google_storage_bucket.notebooks.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

# ---------------------------------------------------------------------------
# Colab Enterprise Runtime Template — Default runtime for notebook execution
#
# This creates a runtime template that the notebook_executor DAG references
# when submitting notebook execution jobs via the Vertex AI API.
#
# NOTE: google_colab_runtime_template requires provider >= 6.x.
# Using a provisioner to stay compatible with the project's v5.x provider.
# ---------------------------------------------------------------------------

resource "null_resource" "colab_runtime_template" {
  provisioner "local-exec" {
    command = <<-EOT
      # Check if runtime template already exists
      if gcloud colab runtime-templates describe monitoring-lab-runtime \
          --project=${var.project_id} \
          --region=${var.region} > /dev/null 2>&1; then
        echo "Runtime template 'monitoring-lab-runtime' already exists — skipping."
      else
        echo "Creating Colab Enterprise runtime template..."
        gcloud colab runtime-templates create monitoring-lab-runtime \
          --project=${var.project_id} \
          --region=${var.region} \
          --display-name="Monitoring Lab Default Runtime" \
          --machine-type=e2-standard-2
        echo "Runtime template created."
      fi
    EOT
  }

  depends_on = [
    google_project_service.apis,
  ]
}
