# ---------------------------------------------------------------------------
# networking.tf — VPC and private connectivity for Datastream ↔ Cloud SQL
#
# Creates:
#   - VPC network for private connectivity
#   - Private service access for Cloud SQL
#   - Private connectivity configuration for Datastream
# ---------------------------------------------------------------------------

resource "google_compute_network" "datastream_vpc" {
  name                    = "monitoring-lab-vpc"
  project                 = var.project_id
  auto_create_subnetworks = true

  depends_on = [
    google_project_service.apis,
  ]
}

# ---------------------------------------------------------------------------
# Private Service Access — allows Cloud SQL to use the VPC
# ---------------------------------------------------------------------------

resource "google_compute_global_address" "private_ip_range" {
  name          = "monitoring-lab-private-ip"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.datastream_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.datastream_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [
    google_project_service.apis,
  ]
}

# ---------------------------------------------------------------------------
# Datastream Private Connectivity
# ---------------------------------------------------------------------------

resource "google_datastream_private_connection" "lab" {
  display_name          = "monitoring-lab-private-conn"
  location              = var.region
  project               = var.project_id
  private_connection_id = "monitoring-lab-private-conn"

  vpc_peering_config {
    vpc    = google_compute_network.datastream_vpc.id
    subnet = "10.3.0.0/29"
  }

  depends_on = [
    google_project_service.apis,
  ]
}
