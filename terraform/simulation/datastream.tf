# ---------------------------------------------------------------------------
# datastream.tf — Datastream CDC stream (Cloud SQL PostgreSQL → BigQuery)
#
# Creates:
#   - Source connection profile (Cloud SQL PostgreSQL)
#   - Destination connection profile (BigQuery)
#   - CDC stream replicating source_db.public.* → BQ raw layer
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Connection Profile: Source (Cloud SQL PostgreSQL)
# ---------------------------------------------------------------------------

resource "google_datastream_connection_profile" "source_pg" {
  display_name          = "monitoring-lab-source-pg"
  location              = var.region
  project               = var.project_id
  connection_profile_id = "monitoring-lab-source-pg"

  postgresql_profile {
    hostname = google_sql_database_instance.source_pg.public_ip_address
    port     = 5432
    username = google_sql_user.datastream_user.name
    password = var.cloudsql_db_password
    database = var.cloudsql_db_name
  }
}

# ---------------------------------------------------------------------------
# Connection Profile: Destination (BigQuery)
# ---------------------------------------------------------------------------

resource "google_datastream_connection_profile" "dest_bq" {
  display_name          = "monitoring-lab-dest-bq"
  location              = var.region
  project               = var.project_id
  connection_profile_id = "monitoring-lab-dest-bq"

  bigquery_profile {}
}

# ---------------------------------------------------------------------------
# Stream: CDC replication
# ---------------------------------------------------------------------------

resource "google_datastream_stream" "lab" {
  display_name = var.datastream_stream_name
  location     = var.region
  project      = var.project_id
  stream_id    = var.datastream_stream_name

  desired_state             = "NOT_STARTED"
  create_without_validation = true

  source_config {
    source_connection_profile = google_datastream_connection_profile.source_pg.id

    postgresql_source_config {
      publication      = "datastream_pub"
      replication_slot = "datastream_slot"

      include_objects {
        postgresql_schemas {
          schema = "public"

          postgresql_tables {
            table = "orders"
          }
        }
      }
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.dest_bq.id

    bigquery_destination_config {
      data_freshness = "900s"

      single_target_dataset {
        dataset_id = "${var.project_id}:${var.bq_dataset_raw}"
      }
    }
  }

  backfill_all {}

  labels = {
    purpose     = "monitoring-lab"
    environment = "learning"
  }

  depends_on = [
    google_bigquery_dataset.raw,
  ]
}
