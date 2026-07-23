# ---------------------------------------------------------------------------
# pubsub.tf — Pub/Sub topic for programmatic alert forwarding
#
# Alerts published here can be consumed by Cloud Functions, Cloud Run,
# or external systems (Slack, PagerDuty) in the future.
# ---------------------------------------------------------------------------

resource "google_pubsub_topic" "alerts" {
  name    = var.pubsub_topic_name
  project = var.project_id

  labels = {
    purpose = "monitoring-lab"
  }

  depends_on = [
    google_project_service.apis,
  ]
}

# Debug subscription — for manually pulling messages during testing
resource "google_pubsub_subscription" "alerts_debug" {
  name    = "${var.pubsub_topic_name}-debug-sub"
  topic   = google_pubsub_topic.alerts.id
  project = var.project_id

  # Short retention for testing
  message_retention_duration = "86400s" # 1 day
  ack_deadline_seconds       = 60

  # Auto-expire if unused for 7 days
  expiration_policy {
    ttl = "604800s" # 7 days
  }

  labels = {
    purpose = "monitoring-lab-debug"
  }
}
