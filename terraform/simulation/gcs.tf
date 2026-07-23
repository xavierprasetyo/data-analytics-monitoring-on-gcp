# ---------------------------------------------------------------------------
# gcs.tf — GCS bucket for the simulated data lake
#
# Creates a bucket to simulate the Data Lake (GCS) layer from the
# data pipeline architecture. Used to test GCS monitoring dashboards.
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "datalake" {
  name          = "${var.project_id}-${var.gcs_datalake_suffix}"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = true

  uniform_bucket_level_access = true

  labels = {
    purpose     = "monitoring-lab"
    environment = "learning"
  }

  depends_on = [
    google_project_service.apis,
  ]
}

# ---------------------------------------------------------------------------
# Upload a sample file so the bucket has measurable storage
# ---------------------------------------------------------------------------

resource "google_storage_bucket_object" "sample_data" {
  name    = "sample-data/README.md"
  content = "# Sample Data Lake\n\nThis bucket simulates the GCS data lake layer.\nUsed for monitoring dashboard testing.\n"
  bucket  = google_storage_bucket.datalake.name
}
