# ---------------------------------------------------------------------------
# main.tf — Provider configuration and API enablement (Monitoring Module)
#
# This module is REUSABLE — it has zero dependencies on the simulation lab.
# Point it at any existing GCP project with the right variables and apply.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------------------------------------
# Enable monitoring-specific APIs (idempotent — safe to re-enable)
# ---------------------------------------------------------------------------

resource "google_project_service" "monitoring_apis" {
  for_each = toset([
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Data source: Default compute service account (for scheduled queries)
# ---------------------------------------------------------------------------

data "google_compute_default_service_account" "default" {
  project = var.project_id
}
