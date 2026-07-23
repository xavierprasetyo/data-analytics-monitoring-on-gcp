# ---------------------------------------------------------------------------
# bigquery.tf — BigQuery dataset for the sample pipeline
# ---------------------------------------------------------------------------

resource "google_bigquery_dataset" "lab" {
  dataset_id  = var.bq_dataset_id
  project     = var.project_id
  location    = var.bq_location
  description = "Monitoring & alerting learning lab — sample pipeline data"

  # Delete all tables when destroying the dataset
  delete_contents_on_destroy = true

  labels = {
    purpose     = "monitoring-lab"
    environment = "learning"
  }

  depends_on = [
    google_project_service.apis,
  ]
}
