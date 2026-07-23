# ---------------------------------------------------------------------------
# cloudsql.tf — Cloud SQL PostgreSQL instance (Datastream CDC source)
#
# Provisions a minimal PostgreSQL instance with:
#   - Logical decoding enabled (required for Datastream CDC)
#   - A replication user for Datastream
#   - A sample "orders" table with data for CDC testing
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "source_pg" {
  name             = var.cloudsql_instance_name
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_15"

  settings {
    tier              = var.cloudsql_tier
    availability_type = "ZONAL"

    # Required for Datastream CDC via logical replication
    database_flags {
      name  = "cloudsql.logical_decoding"
      value = "on"
    }

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.datastream_vpc.id

      authorized_networks {
        name  = "allow-all"
        value = "0.0.0.0/0"
      }
    }

    backup_configuration {
      enabled = false
    }

    disk_size = 10

    user_labels = {
      purpose     = "monitoring-lab"
      environment = "learning"
    }
  }

  deletion_protection = false

  depends_on = [
    google_project_service.apis,
    google_service_networking_connection.private_vpc_connection,
  ]
}

# ---------------------------------------------------------------------------
# Database and user for Datastream
# ---------------------------------------------------------------------------

resource "google_sql_database" "source_db" {
  name     = var.cloudsql_db_name
  project  = var.project_id
  instance = google_sql_database_instance.source_pg.name
}

resource "google_sql_user" "datastream_user" {
  name     = "datastream_user"
  project  = var.project_id
  instance = google_sql_database_instance.source_pg.name
  password = var.cloudsql_db_password
}
