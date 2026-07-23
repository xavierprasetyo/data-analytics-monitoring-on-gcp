# ---------------------------------------------------------------------------
# outputs.tf — Monitoring module outputs
# ---------------------------------------------------------------------------

output "notification_channel_email" {
  description = "Email notification channel ID"
  value       = google_monitoring_notification_channel.email.id
}

output "notification_channel_slack" {
  description = "Slack notification channel ID (empty if Slack is not configured)"
  value       = length(google_monitoring_notification_channel.slack) > 0 ? google_monitoring_notification_channel.slack[0].id : ""
}

output "composer_alert_policies" {
  description = "Composer alerting policies"
  value = {
    dag_run_failures    = google_monitoring_alert_policy.dag_run_failures.display_name
    task_failures       = google_monitoring_alert_policy.task_failures.display_name
    scheduler_heartbeat = google_monitoring_alert_policy.scheduler_heartbeat.display_name
    worker_evictions    = google_monitoring_alert_policy.worker_evictions.display_name
    database_health     = google_monitoring_alert_policy.database_health.display_name
    error_logs          = google_monitoring_alert_policy.error_logs.display_name
    dag_parse_errors    = google_monitoring_alert_policy.dag_parse_errors.display_name
    webserver_health    = google_monitoring_alert_policy.webserver_health.display_name
  }
}

output "datastream_alert_policies" {
  description = "Datastream alerting policies (empty if Datastream monitoring is disabled)"
  value = local.enable_datastream ? {
    throughput_stale  = google_monitoring_alert_policy.datastream_throughput_stale[0].display_name
    unhealthy         = google_monitoring_alert_policy.datastream_unhealthy[0].display_name
    backfill_failures = google_monitoring_alert_policy.datastream_backfill_failures[0].display_name
    high_lag          = google_monitoring_alert_policy.datastream_high_lag[0].display_name
  } : {}
}

output "bigquery_alert_policies" {
  description = "BigQuery alerting policies"
  value = {
    high_slot_time           = google_monitoring_alert_policy.bq_high_slot_time.display_name
    scheduled_query_failures = google_monitoring_alert_policy.bq_scheduled_query_failures.display_name
    data_freshness           = length(google_monitoring_alert_policy.bq_data_freshness) > 0 ? google_monitoring_alert_policy.bq_data_freshness[0].display_name : "disabled"
  }
}

output "dashboards" {
  description = "Cloud Monitoring dashboards"
  value = {
    composer_operational = google_monitoring_dashboard.composer_operational.id
    pipeline_health      = google_monitoring_dashboard.pipeline_health.id
    cost_storage         = google_monitoring_dashboard.cost_storage.id
  }
}

output "monitoring_reports_dataset" {
  description = "BigQuery dataset containing monitoring reports (slot-time audit, storage comparison)"
  value       = google_bigquery_dataset.monitoring_reports.dataset_id
}
