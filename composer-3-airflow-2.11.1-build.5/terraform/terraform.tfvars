# ---------------------------------------------------------------------------
# terraform.tfvars — User-specific values
#
# Update these for your environment before running terraform apply.
# ---------------------------------------------------------------------------

project_id  = "project-sandbox-357505"
region      = "us-central1"
alert_email = "admin@xavierprasetyo.demo.altostrat.com" # TODO: Replace with your email

# Composer settings
composer_env_name      = "monitoring-lab-composer"
composer_image_version = "composer-3-airflow-2.11.1-build.5"

# BigQuery settings
bq_dataset_id = "monitoring_lab"
bq_location   = "US"

# Slack settings (optional — leave webhook empty to skip Slack)
# Get a webhook URL from https://api.slack.com/messaging/webhooks
slack_webhook_url  = ""           # e.g., "https://hooks.slack.com/services/T.../B.../xxx"
slack_channel_name = "#data-alerts"
