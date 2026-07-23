# ---------------------------------------------------------------------------
# monitoring_channels.tf — Notification channels for all alert policies
#
# Creates:
#   - Email notification channel (always)
#   - Slack notification channel (optional — skipped if webhook URL is empty)
#   - Local convenience reference used by all alert policies
# ---------------------------------------------------------------------------

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Pipeline Alerts - Email"
  type         = "email"
  description  = "Email notifications for data pipeline alerts"

  labels = {
    email_address = var.alert_email
  }
}

# ---------------------------------------------------------------------------
# Slack (optional — skipped if webhook URL is empty)
#
# Setup:
#   1. Go to https://api.slack.com/messaging/webhooks
#   2. Create an Incoming Webhook for your workspace/channel
#   3. Set the URL in terraform.tfvars as slack_webhook_url
# ---------------------------------------------------------------------------

resource "google_monitoring_notification_channel" "slack" {
  count        = var.slack_webhook_url != "" ? 1 : 0
  project      = var.project_id
  display_name = "Pipeline Alerts - Slack"
  type         = "slack"
  description  = "Slack notifications for data pipeline alerts"

  labels = {
    channel_name = var.slack_channel_name
  }

  sensitive_labels {
    auth_token = var.slack_webhook_url
  }
}

# ---------------------------------------------------------------------------
# Local: convenience references used by all alert policies
# ---------------------------------------------------------------------------

locals {
  composer_env_filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\""

  notification_channels = concat(
    [google_monitoring_notification_channel.email.id],
    google_monitoring_notification_channel.slack[*].id,
  )
}
