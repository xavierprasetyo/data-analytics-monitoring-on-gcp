# Available GCP Metrics Reference

A comprehensive reference of Cloud Monitoring metrics available **out of the box** for each GCP service used in this project. Use this guide to customize dashboards, create new alerting policies, or monitor additional aspects of your data pipelines.

> **How to use this doc:** Each section lists the built-in metrics for a service, grouped by category. Metrics marked ✅ are **already used** in this project's dashboards or alert policies. Metrics marked ⬜ are **available but not yet used** — add them to your dashboards or alerts as needed.

---

## Table of Contents

- [Cloud Composer (Airflow)](#cloud-composer-airflow)
- [BigQuery](#bigquery)
- [Datastream](#datastream)
- [Cloud Storage (GCS)](#cloud-storage-gcs)
- [Custom Log-Based Metrics](#custom-log-based-metrics)
- [GCP Monitoring Best Practices](#gcp-monitoring-best-practices)
- [How to Query Metrics](#how-to-query-metrics)
- [How to Add a Metric to the Dashboard](#how-to-add-a-metric-to-the-dashboard)

---

## Cloud Composer (Airflow)

> **GCP Documentation:**
> - [Cloud Composer Metrics List](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-composer)
> - [Monitor Environments with Cloud Monitoring](https://cloud.google.com/composer/docs/how-to/managing/monitoring-environments)
> - [Use the Monitoring Dashboard](https://cloud.google.com/composer/docs/composer-3/use-monitoring-dashboard)
>
> **Best Practice Guides:**
> - [Optimize Environment Performance and Costs](https://cloud.google.com/composer/docs/composer-3/optimize-environments)
> - [Scale Composer Environments](https://cloud.google.com/composer/docs/composer-3/scale-environments)
> - [Environment Architecture Overview](https://cloud.google.com/composer/docs/composer-3/environment-architecture)

Cloud Composer metrics use two resource types:
- **`cloud_composer_environment`** — Environment-level metrics (scheduler, database, workers)
- **`cloud_composer_workflow`** — Per-DAG metrics (run counts)
- **`cloud_composer_workload`** — Workload-level resource usage (memory, CPU)

### Environment Health

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `composer.googleapis.com/environment/database_health` | Whether the Airflow metadata database is healthy (boolean gauge) | `database_health_state` | `ALIGN_FRACTION_TRUE` |
| ✅ | `composer.googleapis.com/environment/scheduler_heartbeat_count` | Count of scheduler heartbeats | — | `ALIGN_SUM` |
| ✅ | `composer.googleapis.com/environment/web_server/health` | Whether the Airflow webserver is healthy (boolean gauge) | — | `ALIGN_FRACTION_TRUE` |
| ✅ | `composer.googleapis.com/environment/dagbag_size` | Number of DAGs loaded in the environment | — | `ALIGN_MEAN` |
| ⬜ | `composer.googleapis.com/environment/api/request_count` | Number of Airflow REST API requests | `response_code`, `method` | `ALIGN_SUM` |
| ⬜ | `composer.googleapis.com/environment/api/request_latencies` | Latency of Airflow REST API requests | `response_code`, `method` | `ALIGN_PERCENTILE_99` |
| ⬜ | `composer.googleapis.com/environment/healthy` | Overall environment health (boolean) | — | `ALIGN_FRACTION_TRUE` |

### DAG Runs & Tasks

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `composer.googleapis.com/workflow/run_count` | Number of DAG runs (resource: `cloud_composer_workflow`) | `state` (success, failed), `workflow_name` | `ALIGN_SUM` |
| ✅ | `composer.googleapis.com/environment/finished_task_instance_count` | Count of finished task instances | `state` (success, failed, skipped, upstream_failed) | `ALIGN_SUM` |
| ✅ | `composer.googleapis.com/environment/unfinished_task_instances` | Currently running or queued task instances | — | `ALIGN_MAX` |
| ⬜ | `composer.googleapis.com/workflow/run_duration` | Duration of DAG runs | `state`, `workflow_name` | `ALIGN_PERCENTILE_99` |
| ⬜ | `composer.googleapis.com/workflow/task/run_duration` | Duration of individual task instances | `state`, `task_name`, `workflow_name` | `ALIGN_PERCENTILE_99` |
| ⬜ | `composer.googleapis.com/environment/task_queue_length` | Number of tasks in the executor queue | — | `ALIGN_MAX` |
| ⬜ | `composer.googleapis.com/environment/num_executors` | Number of running Celery executors | — | `ALIGN_MEAN` |

### DAG Processing

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `composer.googleapis.com/environment/dag_processing/total_parse_time` | Total time to parse all DAG files (seconds) | — | `ALIGN_MEAN` |
| ⬜ | `composer.googleapis.com/environment/dag_processing/processes` | Number of DAG file processor processes running | — | `ALIGN_MEAN` |
| ⬜ | `composer.googleapis.com/environment/dag_processing/parse_time` | Per-file parse time | `file_path` | `ALIGN_PERCENTILE_99` |
| ⬜ | `composer.googleapis.com/environment/dag_processing/import_errors` | Number of DAG import errors | — | `ALIGN_MAX` |

### Workers & Resources

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `composer.googleapis.com/environment/worker/pod_eviction_count` | Number of worker pods evicted | — | `ALIGN_SUM` |
| ✅ | `composer.googleapis.com/workload/memory/bytes_used` | Memory bytes used by workloads (resource: `cloud_composer_workload`) | `component` | `ALIGN_MEAN` |
| ✅ | `composer.googleapis.com/workload/memory/quota` | Memory limit for workloads (resource: `cloud_composer_workload`) | `component` | `ALIGN_MEAN` |
| ⬜ | `composer.googleapis.com/workload/cpu/usage_time` | CPU seconds used by workloads | `component` | `ALIGN_RATE` |
| ⬜ | `composer.googleapis.com/workload/cpu/quota` | CPU quota for workloads | `component` | `ALIGN_MEAN` |
| ⬜ | `composer.googleapis.com/environment/executor/open_slots` | Number of open execution slots | — | `ALIGN_MEAN` |

### Scheduler

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ⬜ | `composer.googleapis.com/environment/scheduler/running_dags` | Number of running DAGs | — | `ALIGN_MEAN` |
| ⬜ | `composer.googleapis.com/environment/scheduler/zombies_killed` | Number of zombie tasks killed | — | `ALIGN_SUM` |

---

## BigQuery

> **GCP Documentation:**
> - [BigQuery Metrics List](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-bigquery)
> - [Monitor BigQuery with Cloud Monitoring](https://cloud.google.com/bigquery/docs/monitoring)
> - [INFORMATION_SCHEMA Reference](https://cloud.google.com/bigquery/docs/information-schema-intro)
>
> **Best Practice Guides:**
> - [Best Practices for Performance](https://cloud.google.com/bigquery/docs/best-practices-performance-overview)
> - [Best Practices for Controlling Costs](https://cloud.google.com/bigquery/docs/best-practices-costs)
> - [Best Practices for Optimizing Storage](https://cloud.google.com/bigquery/docs/best-practices-storage)
> - [Workload Management Best Practices](https://cloud.google.com/blog/topics/developers-practitioners/bigquery-workload-management-best-practices)

BigQuery metrics use several resource types:
- **`bigquery_project`** — Project-level job and slot metrics
- **`bigquery_dataset`** — Per-dataset storage metrics
- **`global`** — Query-level metrics (bytes scanned)

### Query Performance

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `bigquery.googleapis.com/query/execution_times` | Query execution times in seconds | `priority` (INTERACTIVE, BATCH) | `ALIGN_PERCENTILE_99` |
| ✅ | `bigquery.googleapis.com/query/scanned_bytes` | Bytes processed by queries | — | `ALIGN_SUM` |
| ✅ | `bigquery.googleapis.com/query/scanned_bytes_billed` | Bytes billed for queries (after min billing applied) | — | `ALIGN_SUM` |
| ⬜ | `bigquery.googleapis.com/query/count` | Number of queries run | `priority` | `ALIGN_SUM` |
| ⬜ | `bigquery.googleapis.com/query/statement_scanned_bytes` | Bytes scanned per SQL statement type | `statement_type` (SELECT, INSERT, etc.) | `ALIGN_SUM` |
| ⬜ | `bigquery.googleapis.com/query/statement_scanned_bytes_billed` | Bytes billed per SQL statement type | `statement_type` | `ALIGN_SUM` |

### Slots & Jobs

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `bigquery.googleapis.com/slots/total_available` | Total slots available to the project | — | `ALIGN_MEAN` |
| ✅ | `bigquery.googleapis.com/slots/allocated_for_project` | Slots currently allocated to the project | — | `ALIGN_MEAN` |
| ✅ | `bigquery.googleapis.com/job/num_in_flight` | Number of in-progress jobs | `state` (running, pending) | `ALIGN_MEAN` |
| ⬜ | `bigquery.googleapis.com/slots/allocated_for_reservation` | Slots allocated per reservation | `reservation_id` | `ALIGN_MEAN` |
| ⬜ | `bigquery.googleapis.com/slots/total_allocated_for_reservation` | Total slots used by reservation + spill | `reservation_id` | `ALIGN_MEAN` |

### Storage

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `bigquery.googleapis.com/storage/stored_bytes` | Total bytes stored per dataset (daily gauge) | — | `ALIGN_MEAN` (86400s) |
| ✅ | `bigquery.googleapis.com/storage/table_count` | Number of tables per dataset (daily gauge) | — | `ALIGN_MEAN` (86400s) |
| ✅ | `bigquery.googleapis.com/storage/uploaded_bytes` | Bytes uploaded (streaming inserts, load jobs) | — | `ALIGN_SUM` |
| ✅ | `bigquery.googleapis.com/storage/uploaded_row_count` | Rows uploaded (streaming inserts, load jobs) | — | `ALIGN_SUM` |

### INFORMATION_SCHEMA (SQL-Based)

These are not Cloud Monitoring metrics but SQL-queryable metadata tables. This project uses them via BigQuery Scheduled Queries:

| Status | Table | Description | Used For |
|--------|-------|-------------|----------|
| ✅ | `INFORMATION_SCHEMA.JOBS` | Job history including slot usage, bytes processed | Daily slot-time audit report |
| ✅ | `INFORMATION_SCHEMA.TABLE_STORAGE` | Physical vs logical storage per table | Daily storage billing comparison |
| ⬜ | `INFORMATION_SCHEMA.JOBS_TIMELINE` | Per-second slot usage breakdown | Fine-grained slot analysis |
| ⬜ | `INFORMATION_SCHEMA.STREAMING_TIMELINE` | Streaming buffer statistics | Streaming insert monitoring |
| ⬜ | `INFORMATION_SCHEMA.TABLES` | Table metadata (creation, modification times) | Data freshness checks |

---

## Datastream

> **GCP Documentation:**
> - [Datastream Metrics List](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-datastream)
> - [Monitor Datastream Streams](https://cloud.google.com/datastream/docs/view-stream-details)
> - [Datastream Overview](https://cloud.google.com/datastream/docs/overview)
>
> **Best Practice Guides:**
> - [Datastream Best Practices](https://cloud.google.com/datastream/docs/best-practices)
> - [CDC and Replication to BigQuery](https://cloud.google.com/datastream/docs/configure-your-source-mysql-database) (MySQL)
> - [CDC and Replication to BigQuery](https://cloud.google.com/datastream/docs/configure-your-source-postgresql-database) (PostgreSQL)

Datastream metrics use the resource type: **`datastream.googleapis.com/Stream`**

### Throughput & Latency

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `datastream.googleapis.com/stream/event_count` | Total CDC events received | `source_object` | `ALIGN_RATE` or `ALIGN_SUM` |
| ✅ | `datastream.googleapis.com/stream/freshness` | Current replication freshness (lag in seconds) | — | `ALIGN_MAX` |
| ✅ | `datastream.googleapis.com/stream/total_latencies` | End-to-end replication latency | — | `ALIGN_PERCENTILE_99` |
| ✅ | `datastream.googleapis.com/stream/unsupported_event_count` | Events that could not be replicated | `source_object` | `ALIGN_SUM` |
| ✅ | `datastream.googleapis.com/stream/bytes_count` | Bytes streamed | — | `ALIGN_RATE` |
| ⬜ | `datastream.googleapis.com/stream/throughput` | Overall throughput (events/sec) | — | `ALIGN_MEAN` |

### Stream Health

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ⬜ | `datastream.googleapis.com/stream/source_latencies` | Latency at the source side | — | `ALIGN_PERCENTILE_99` |
| ⬜ | `datastream.googleapis.com/stream/destination_latencies` | Latency at the destination side | — | `ALIGN_PERCENTILE_99` |

---

## Cloud Storage (GCS)

> **GCP Documentation:**
> - [Cloud Storage Metrics List](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-storage)
> - [Overview of Monitoring in Cloud Storage](https://cloud.google.com/storage/docs/monitoring)
> - [Object Lifecycle Management](https://cloud.google.com/storage/docs/lifecycle)
>
> **Best Practice Guides:**
> - [Best Practices for Cloud Storage](https://cloud.google.com/storage/docs/best-practices)
> - [Request Rate and Access Distribution](https://cloud.google.com/storage/docs/request-rate)
> - [Cloud Audit Logs with Cloud Storage](https://cloud.google.com/storage/docs/audit-logging)

GCS metrics use the resource type: **`gcs_bucket`**

### API & Network

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `storage.googleapis.com/api/request_count` | API requests per bucket | `method`, `response_code` | `ALIGN_SUM` |
| ✅ | `storage.googleapis.com/network/sent_bytes_count` | Network bytes sent (egress) | `method`, `response_code` | `ALIGN_SUM` |
| ⬜ | `storage.googleapis.com/network/received_bytes_count` | Network bytes received (ingress) | `method`, `response_code` | `ALIGN_SUM` |

### Storage Size

| Status | Metric Type | Description | Labels | Recommended Aligner |
|--------|-------------|-------------|--------|---------------------|
| ✅ | `storage.googleapis.com/storage/total_bytes` | Total bytes stored per bucket (daily gauge) | `storage_class` | `ALIGN_MEAN` (86400s) |
| ✅ | `storage.googleapis.com/storage/object_count` | Number of objects per bucket (daily gauge) | `storage_class` | `ALIGN_MEAN` (86400s) |
| ⬜ | `storage.googleapis.com/authz/acl_based_object_access_count` | Object accesses via ACLs | — | `ALIGN_SUM` |
| ⬜ | `storage.googleapis.com/authz/object_specific_acl_mutation_count` | ACL mutations | — | `ALIGN_SUM` |

---

## Custom Log-Based Metrics

These are **custom metrics created by this project** (not built-in GCP metrics). They are defined in [monitoring_composer.tf](../terraform/monitoring/monitoring_composer.tf) and [monitoring_datastream.tf](../terraform/monitoring/monitoring_datastream.tf).

| Metric Name | Resource Type | Filter | Extracted Labels | Used In |
|-------------|---------------|--------|------------------|---------|
| `logging.googleapis.com/user/composer_task_errors` | `cloud_composer_environment` | `severity>=ERROR AND textPayload=~"alert_type.*TASK_FAILURE"` | `dag_id`, `task_id`, `alert_type` | Dashboard + Alert |
| `logging.googleapis.com/user/composer_dag_parse_errors` | `cloud_composer_environment` | `severity>=ERROR AND textPayload=~"DagFileProcessorProcess\|DagBag\|import_errors"` | — | Dashboard + Alert |
| `logging.googleapis.com/user/bq_scheduled_query_failures` | `bigquery_resource` | `severity>=ERROR AND protoPayload.methodName=~"datatransfer"` | `transfer_config_name` | Dashboard + Alert |
| `logging.googleapis.com/user/datastream_stream_errors` | `datastream.googleapis.com/Stream` | `severity>=ERROR` | `stream_id` | Alert |
| `logging.googleapis.com/user/datastream_backfill_errors` | `datastream.googleapis.com/Stream` | `severity>=ERROR AND textPayload=~"backfill"` | — | Alert |

---

## GCP Monitoring Best Practices

These are the key best practices from the official GCP documentation for monitoring the services used in this project.

> **Official Guides:**
> - [Cloud Monitoring Overview](https://cloud.google.com/monitoring/docs)
> - [Alerting Overview](https://cloud.google.com/monitoring/alerts)
> - [MQL Alerting Best Practices](https://cloud.google.com/monitoring/mql/alerts)
> - [Creating Log-Based Metrics](https://cloud.google.com/logging/docs/logs-based-metrics)

### Cloud Composer

From the [Monitoring Environments](https://cloud.google.com/composer/docs/how-to/managing/monitoring-environments) and [Optimize Performance](https://cloud.google.com/composer/docs/composer-3/optimize-environments) guides:

| Best Practice | Why | Key Metric(s) |
|---|---|---|
| **Monitor DAG parse times** — alert if total parse time exceeds 10s | Overloaded schedulers miss scheduling cycles, causing cascading delays | `dag_processing/total_parse_time` |
| **Track scheduler heartbeats** — alert on absence | A silent scheduler means no tasks get scheduled at all | `scheduler_heartbeat_count` |
| **Watch worker memory Used vs Limit** — alert when Used/Limit > 80% | Worker pod evictions cause task failures and retries | `workload/memory/bytes_used` vs `workload/memory/quota` |
| **Avoid `Variable.get()` in top-level DAG code** | Variables fetched at parse time hit the DB on every parse cycle, inflating parse times | `dag_processing/total_parse_time` |
| **Keep DAGs atomic and idempotent** | Enables safe retries and makes troubleshooting predictable | `finished_task_instance_count` |
| **Use the Monitoring tab in the Console** — click the bell icon on any metric card | Fastest way to create an alert from the built-in dashboard | — |
| **Set up cross-project monitoring with Terraform** | Maintains consistent alerting across environments | — |

### BigQuery

From the [Monitoring Guide](https://cloud.google.com/bigquery/docs/monitoring) and [Performance Best Practices](https://cloud.google.com/bigquery/docs/best-practices-performance-overview):

| Best Practice | Why | Key Metric(s) / Tool |
|---|---|---|
| **Monitor slot utilization** — alert when allocated approaches available | Slot contention slows all queries in the project | `slots/allocated_for_project` vs `slots/total_available` |
| **Track bytes scanned and billed** | Catches runaway queries early — a single `CROSS JOIN` can scan TBs | `query/scanned_bytes_billed` |
| **Use `INFORMATION_SCHEMA.JOBS`** for deep analysis | Provides per-query slot-time, bytes, user, and statement type — more detail than monitoring metrics | `INFORMATION_SCHEMA.JOBS` |
| **Avoid `SELECT *`** — project only needed columns | Reduces I/O, materialization, and billed bytes | `query/scanned_bytes_billed` |
| **Partition and cluster tables** | Limits data scanned per query; clustering colocates related rows | `query/scanned_bytes` |
| **Export audit logs to BigQuery** for cost analysis | Enables custom reporting on who ran what, when, and at what cost | Cloud Audit Logs |
| **Use Gemini Cloud Assist** (if available) | Analyzes reservations, identifies performance bottlenecks via natural language | BigQuery Admin Panel |

### Datastream

From the [Monitor Datastream](https://cloud.google.com/datastream/docs/view-stream-details) and [Best Practices](https://cloud.google.com/datastream/docs/best-practices) guides:

| Best Practice | Why | Key Metric(s) |
|---|---|---|
| **Monitor Data Freshness** — alert when freshness exceeds SLA | A value > 0 means Datastream is behind; 0 means fully caught up | `stream/freshness` |
| **Track System Latency separately from Total Latency** | Helps distinguish source-side slowness from Datastream processing delays | `stream/source_latencies` vs `stream/total_latencies` |
| **Alert on Unsupported Events** | Unsupported events mean data is being dropped — potential silent data loss | `stream/unsupported_event_count` |
| **Use multiple streams for PostgreSQL** | Prevents head-of-line blocking since PostgreSQL uses a single logical replication slot | `stream/event_count` per stream |
| **Set meaningful thresholds** — avoid alert fatigue | Minor transient spikes are normal; alert on sustained deviations | — |
| **Create alerts directly from the Stream details page** | The Data Freshness graph has a built-in "Create alerting policy" link | — |

### Cloud Storage

From the [Overview of Monitoring](https://cloud.google.com/storage/docs/monitoring) and [Best Practices](https://cloud.google.com/storage/docs/best-practices) guides:

| Best Practice | Why | Key Metric(s) |
|---|---|---|
| **Monitor 4xx and 5xx error rates** | 4xx = permissions/request issues; 5xx = Google-side issues requiring action | `api/request_count` (filter by `response_code`) |
| **Track egress bandwidth** | Egress costs can spike unexpectedly with large reads or cross-region transfers | `network/sent_bytes_count` |
| **Use the Observability tab** on bucket details | Quickest way to check per-bucket health without writing MQL | — |
| **Estimate operations/sec before scaling** | Prevents hitting rate limits (5,000 ops/sec/prefix initially) | `api/request_count` |
| **Enable Cloud Audit Logs for sensitive buckets** | Tracks who accessed what and when — critical for compliance | Cloud Audit Logs |
| **Define SLOs in Cloud Monitoring** | Aligns alerting with business expectations using SRE practices | — |

### General Cloud Monitoring

From the [Alerting Overview](https://cloud.google.com/monitoring/alerts) and [MQL Best Practices](https://cloud.google.com/monitoring/mql/alerts):

| Best Practice | Why |
|---|---|
| **Use `group_by_fields` in aggregations** | Preserves label values (dag_id, task_id) through the aggregation pipeline — without this, labels collapse to `(null)` |
| **Set `duration` > 0s for infrastructure alerts** | Prevents single-point false positives; e.g., 300s duration means the condition must hold for 5 minutes |
| **Use `condition_absent` for heartbeat-style metrics** | Catches complete failures (scheduler down, stream stopped) rather than threshold violations |
| **Include context in alert documentation** | Use `${metric.labels.X}` templates so on-call engineers see dag_id, task_id etc. directly in the notification |
| **Auto-close alerts** | Set `auto_close` (e.g., 1800s) to prevent stale incident noise |
| **Narrow log-based metric filters** | Only match your structured JSON, not random stack traces — prevents `(null)` label extraction |
| **Manage alerts as code (Terraform)** | Console edits are overwritten on `terraform apply`; keep Terraform as source of truth |

---

## How to Query Metrics

### Using Metrics Explorer (Console)

1. Go to **Cloud Monitoring → Metrics Explorer**
   - [Direct link](https://console.cloud.google.com/monitoring/metrics-explorer)
2. In the **Metric** field, type the metric name (e.g., `composer.googleapis.com/environment/database_health`)
3. Set the **Resource type** filter (e.g., `cloud_composer_environment`)
4. Adjust the **Alignment Period** and **Aligner** as recommended in the tables above
5. Add **Filters** to scope to your environment (e.g., `resource.labels.environment_name = "monitoring-lab-composer"`)

### Using `gcloud` CLI

```bash
# List all available Composer metrics
gcloud monitoring metrics-descriptors list \
    --project="YOUR_PROJECT_ID" \
    --filter='metric.type = starts_with("composer.googleapis.com/")'

# List all available BigQuery metrics
gcloud monitoring metrics-descriptors list \
    --project="YOUR_PROJECT_ID" \
    --filter='metric.type = starts_with("bigquery.googleapis.com/")'

# List all available Datastream metrics
gcloud monitoring metrics-descriptors list \
    --project="YOUR_PROJECT_ID" \
    --filter='metric.type = starts_with("datastream.googleapis.com/")'

# List all available GCS metrics
gcloud monitoring metrics-descriptors list \
    --project="YOUR_PROJECT_ID" \
    --filter='metric.type = starts_with("storage.googleapis.com/")'

# List all custom log-based metrics
gcloud logging metrics list --project="YOUR_PROJECT_ID"
```

### Using MQL (Monitoring Query Language)

```
# Example: Fetch failed DAG runs by workflow name
fetch cloud_composer_workflow
| metric 'composer.googleapis.com/workflow/run_count'
| filter (metric.state == 'failed')
| align delta(5m)
| every 5m
| group_by [resource.workflow_name], [value_sum: sum(val())]
| top 10
```

---

## How to Add a Metric to the Dashboard

### Option 1: Add via Terraform

Add a new tile to the relevant dashboard `.tf` file. Example — adding a **Task Queue Length** chart to [dashboard_composer.tf](../terraform/monitoring/dashboard_composer.tf):

```hcl
{
  xPos   = 0
  yPos   = 54    # Place below existing tiles
  width  = 24
  height = 8
  widget = {
    title = "Task Queue Length"
    xyChart = {
      dataSets = [
        {
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = "resource.type = \"cloud_composer_environment\" AND metric.type = \"composer.googleapis.com/environment/task_queue_length\""
              aggregation = {
                alignmentPeriod  = "300s"
                perSeriesAligner = "ALIGN_MAX"
              }
            }
          }
          plotType       = "LINE"
          legendTemplate = "Queue length"
        }
      ]
      yAxis = {
        label = "Tasks"
        scale = "LINEAR"
      }
    }
  }
}
```

Then run:

```bash
cd terraform/monitoring
terraform plan    # Preview
terraform apply   # Deploy
```

### Option 2: Add via Console

1. Go to **Cloud Monitoring → Dashboards**
2. Open the target dashboard (e.g., "Composer Operational Health")
3. Click **Edit Dashboard** (pencil icon)
4. Click **+ Add Widget**
5. Select chart type (Line, Bar, Scorecard, etc.)
6. Search for the metric and configure filters/aggregation
7. Click **Apply** then **Save**

> [!WARNING]
> Console edits will be **overwritten** on the next `terraform apply`. For persistent changes, edit the Terraform files.

### Option 3: Create a New Alert Policy

Example — alerting on high task queue length:

```hcl
resource "google_monitoring_alert_policy" "high_task_queue" {
  project      = var.project_id
  display_name = "Composer - High Task Queue"
  combiner     = "OR"
  enabled      = true
  severity     = "WARNING"

  documentation {
    content   = "Task queue length exceeds 50. Tasks may be backing up."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Task queue > 50"

    condition_threshold {
      filter          = "resource.type = \"cloud_composer_environment\" AND metric.type = \"composer.googleapis.com/environment/task_queue_length\""
      comparison      = "COMPARISON_GT"
      threshold_value = 50
      duration        = "300s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.notification_channels
}
```

---

## Quick Reference Links

| Service | Metrics List | Monitoring Guide | Best Practices |
|---------|-------------|-----------------|----------------|
| Cloud Composer | [All Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-composer) | [Monitor Environments](https://cloud.google.com/composer/docs/how-to/managing/monitoring-environments) | [Optimize Performance](https://cloud.google.com/composer/docs/composer-3/optimize-environments) |
| BigQuery | [All Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-bigquery) | [Monitoring Guide](https://cloud.google.com/bigquery/docs/monitoring) | [Performance Best Practices](https://cloud.google.com/bigquery/docs/best-practices-performance-overview) |
| Datastream | [All Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-datastream) | [Stream Details](https://cloud.google.com/datastream/docs/view-stream-details) | [Datastream Best Practices](https://cloud.google.com/datastream/docs/best-practices) |
| Cloud Storage | [All Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-storage) | [Monitoring Overview](https://cloud.google.com/storage/docs/monitoring) | [Storage Best Practices](https://cloud.google.com/storage/docs/best-practices) |
| Cloud Logging | [Log-Based Metrics](https://cloud.google.com/logging/docs/logs-based-metrics) | [Creating Metrics](https://cloud.google.com/logging/docs/logs-based-metrics/create-counter) | — |
| Cloud Monitoring | [MQL Reference](https://cloud.google.com/monitoring/mql) | [Alerting Overview](https://cloud.google.com/monitoring/alerts) | [MQL Alerting Best Practices](https://cloud.google.com/monitoring/mql/alerts) |
