# ---------------------------------------------------------------------------
# bigquery.tf — BigQuery datasets for the multi-layer data warehouse
#
# Creates 3 datasets matching the data pipeline architecture:
#   - Raw layer:     Datastream CDC destination
#   - Silver layer:  Transformed / cleaned data
#   - Datamart:      Aggregated data for BI consumption
# ---------------------------------------------------------------------------

resource "google_bigquery_dataset" "raw" {
  dataset_id  = var.bq_dataset_raw
  project     = var.project_id
  location    = var.bq_location
  description = "Raw layer — Datastream CDC destination"

  delete_contents_on_destroy = true

  labels = {
    purpose     = "monitoring-lab"
    layer       = "raw"
    environment = "learning"
  }

  depends_on = [
    google_project_service.apis,
  ]
}

resource "google_bigquery_dataset" "silver" {
  dataset_id  = var.bq_dataset_silver
  project     = var.project_id
  location    = var.bq_location
  description = "Silver layer — transformed and cleaned data"

  delete_contents_on_destroy = true

  labels = {
    purpose     = "monitoring-lab"
    layer       = "silver"
    environment = "learning"
  }

  depends_on = [
    google_project_service.apis,
  ]
}

resource "google_bigquery_dataset" "datamart" {
  dataset_id  = var.bq_dataset_datamart
  project     = var.project_id
  location    = var.bq_location
  description = "Datamart layer — aggregated data for BI consumption"

  delete_contents_on_destroy = true

  labels = {
    purpose     = "monitoring-lab"
    layer       = "datamart"
    environment = "learning"
  }

  depends_on = [
    google_project_service.apis,
  ]
}
