# ---------------------------------------------------------------------------
# cloudrun.tf — Cloud Run service for the Go load generator
#
# Deploys the load generator container that connects to Cloud SQL
# via Serverless VPC Access connector over the private network.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Enable additional APIs for Cloud Run + Artifact Registry
# ---------------------------------------------------------------------------

resource "google_project_service" "cloudrun_apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "vpcaccess.googleapis.com",
    "cloudbuild.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Artifact Registry — Docker repository for the load generator image
# ---------------------------------------------------------------------------

resource "google_artifact_registry_repository" "loadgen" {
  project       = var.project_id
  location      = var.region
  repository_id = "loadgen"
  format        = "DOCKER"
  description   = "Container images for the monitoring lab load generator"

  depends_on = [google_project_service.cloudrun_apis]
}

# ---------------------------------------------------------------------------
# Serverless VPC Access Connector — allows Cloud Run to reach Cloud SQL
# ---------------------------------------------------------------------------

resource "google_vpc_access_connector" "connector" {
  name          = "monitoring-lab-connector"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.datastream_vpc.name
  ip_cidr_range = "10.8.0.0/28"

  depends_on = [google_project_service.cloudrun_apis]
}

# ---------------------------------------------------------------------------
# Cloud Run Service — Go load generator
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "loadgen" {
  name     = "loadgen"
  project  = var.project_id
  location = var.region

  template {
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/loadgen/loadgen:latest"

      ports {
        container_port = 8080
      }

      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.source_pg.private_ip_address
      }
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      env {
        name  = "DB_USER"
        value = "datastream_user"
      }
      env {
        name  = "DB_PASS"
        value = var.cloudsql_db_password
      }
      env {
        name  = "DB_NAME"
        value = var.cloudsql_db_name
      }
      env {
        name  = "INTERVAL_SECONDS"
        value = "5"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }
  }

  depends_on = [
    google_project_service.cloudrun_apis,
    google_artifact_registry_repository.loadgen,
    google_sql_database.source_db,
    google_sql_user.datastream_user,
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}
