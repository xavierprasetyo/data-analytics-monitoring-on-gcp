# Data Analytics Monitoring & Alerting — Learning Lab

A hands-on project to learn how to set up **production-grade GCP monitoring and alerting** for a complete data pipeline: CDC ingestion, BigQuery transformations, notebook execution, and Cloud Composer orchestration. All infrastructure is managed with **Terraform** — two `terraform apply` commands to set up, two `terraform destroy` to tear down.

> **Tech Stack**: Cloud Composer 3 · Apache Airflow 2.11.1 · Image `composer-3-airflow-2.11.1-build.5` · Cloud SQL PostgreSQL 15 · Datastream · BigQuery · Cloud Run (Go) · Vertex AI / Colab Enterprise

## What You'll Build

An end-to-end data pipeline with **CDC ingestion → RAW → SILVER → DATAMART** layers, a **notebook execution framework**, and **centralized monitoring** that automatically covers every DAG, BigQuery job, and Datastream stream — without per-DAG callbacks:

```
 Cloud Run (Go)         Cloud SQL          Datastream (CDC)
 Load Generator    →    PostgreSQL 15  →   Streaming Replication
 (5 orders/cycle)       (orders table)     (inserts + updates)
                                                   |
                                                   v
+-------------------+    +-------------------+    +-----------------------+
|   raw_to_silver   |←---|  BigQuery RAW     |←---|   CDC replica tables  |
|  (every 15 min)   |    | monitoring_lab_raw|    |   (auto-populated)    |
|  MERGE + dedup    |    +-------------------+    +-----------------------+
+-------------------+
        |
        v
+-------------------+    +-----------------------+
| silver_to_datamart|───→|   Datamart Tables      |
|    (hourly)       |    |  revenue_by_product    |
|  Aggregation      |    |  order_status_summary  |
+-------------------+    +-----------------------+

+-------------------+
| notebook_executor |    Executes Colab Enterprise / Vertex AI notebooks
|  (configurable)   |    via YAML registry — deferrable (frees worker slots)
+-------------------+

        Chaos injection points in all production DAGs
        (controlled via Airflow Variables)
                      |
                      v
+-----------------------------------------------+
|         Global Failure Listener Plugin         |
|   Catches ALL task failures across ALL DAGs    |
|   Emits structured JSON → Cloud Logging        |
+-----------------------------------------------+
                      |
                      v
+-----------------------------------------------+
|        Cloud Monitoring & Alerting Layer        |
|  Composer alerts · BigQuery alerts · Datastream |
|  alerts · 3 dashboards · Email / Slack / Pub/Sub|
+-----------------------------------------------+
```

### Two-Module Terraform Architecture

The project uses **two independent Terraform modules** that can be deployed separately:

| Module | Purpose | Key Resources |
|---|---|---|
| **`terraform/simulation`** | Provisions the full data pipeline infrastructure | Cloud Composer 3, Cloud SQL, Datastream, BigQuery (3 datasets), Cloud Run, GCS, Pub/Sub, VPC networking |
| **`terraform/monitoring`** | Reusable monitoring & alerting layer | 3 dashboards, 15+ alert policies, log-based metrics, scheduled queries, notification channels |

> **Why two modules?** The monitoring module is **reusable** — it has zero dependencies on the simulation lab. Point it at any existing GCP project with the right variables and `terraform apply` to get full observability.

### Resources Created

#### Simulation Module (`terraform/simulation`)

| Resource | What It Does |
|---|---|
| Cloud Composer 3 | Managed Airflow 2.11.1 environment |
| Cloud SQL PostgreSQL 15 | Source database with CDC logical replication |
| Datastream | CDC streaming from Cloud SQL → BigQuery |
| BigQuery (3 datasets) | `monitoring_lab_raw`, `monitoring_lab_silver`, `monitoring_lab_datamart` |
| Cloud Run (Go) | Load generator — inserts/updates orders every 5 seconds |
| GCS Bucket | Data lake storage |
| Pub/Sub Topic + Subscription | Programmatic alert forwarding + debug subscription |
| VPC + Private Service Connection | Private networking for Cloud SQL and Datastream |

#### Monitoring Module (`terraform/monitoring`)

| Resource | What It Does |
|---|---|
| Email Notification Channel | Email alerts to your inbox |
| Slack Notification Channel | (Optional) Slack alerts via webhook |
| 8 Composer Alerting Policies | DAG failures, task failures, scheduler, workers, database, webserver, error logs, parse errors |
| 3 BigQuery Alerting Policies | High slot-time jobs, scheduled query failures, data freshness |
| 4 Datastream Alerting Policies | Throughput stale, unhealthy stream, backfill failures, high replication lag |
| 3 Log-based Metrics | Composer task errors, DAG parse errors, scheduled query failures |
| 3 Cloud Monitoring Dashboards | Composer operational health, pipeline health, cost & storage |
| BigQuery Reporting Dataset | Scheduled queries for slot-time audit and storage comparison |

---

## How Alerts Are Captured, Processed, and Sent

This is the end-to-end flow from a task failure to you receiving an alert email with the `dag_id`, `task_id`, and exception details:

### Step-by-Step Alert Flow

```
                         [1] TASK FAILURE OCCURS
                                    |
                                    v
                     +--------------------------+
                     |  [2] Global Listener     |  <- plugins/global_failure_listener.py
                     |     @hookimpl            |
                     |  on_task_instance_failed |
                     +------------+-------------+
                                    |
                                    |  Emits structured JSON:
                                    |  {
                                    |    "alert_type": "TASK_FAILURE",
                                    |    "dag_id": "raw_to_silver",
                                    |    "task_id": "chaos_post_merge",
                                    |    "exception": "Chaos fault injection",
                                    |    "log_url": "https://...",
                                    |    "timestamp": "2026-05-22T01:42:07Z"
                                    |  }
                                    v
                     +--------------------------+
                     |  [3] Cloud Logging       |
                     |  Receives ERROR-level log|
                     |  with textPayload = JSON |
                     +------------+-------------+
                                    |
                                    |  Log filter matches:
                                    |  resource.type="cloud_composer_environment"
                                    |  severity>=ERROR
                                    |  textPayload=~"alert_type.*TASK_FAILURE"
                                    v
                     +--------------------------+
                     |  [4] Log-based Metric    |  <- "composer_task_errors"
                     |  Counts matching entries |
                     |  Extracts labels via     |
                     |  REGEXP_EXTRACT:         |
                     |    dag_id -> regex       |
                     |    task_id -> regex      |
                     |    alert_type -> regex   |
                     +------------+-------------+
                                    |
                                    |  Creates time series:
                                    |  metric=composer_task_errors
                                    |  labels={dag_id, task_id, alert_type}
                                    |  value=1
                                    v
                     +--------------------------+
                     |  [5] Alert Policy        |  <- "Composer - Error Logs Detected"
                     |  Condition: count > 0    |
                     |  Aggregation: ALIGN_SUM  |
                     |  group_by: dag_id,       |
                     |    task_id, alert_type   |
                     |  (preserves label values)|
                     +------------+-------------+
                                    |
                                    |  Policy documentation template:
                                    |  "DAG ID: ${metric.labels.dag_id}"
                                    |  "Task ID: ${metric.labels.task_id}"
                                    v
                     +--------------------------+
                     | [6] Notification Channel |
                     |                          |
                     |  - Email (configured)    |
                     |  - Slack (optional)      |
                     |  - Pub/Sub (programmatic)|
                     +--------------------------+
```

### Why This Design?

| Design Choice | Rationale |
|---|---|
| **Global listener** (not per-DAG callbacks) | Covers ALL DAGs automatically — past, present, and future. No code changes needed per DAG. |
| **Structured JSON logs** (not direct email/Slack) | Decouples alerting from notification. Add/remove channels in one place (Terraform), not in every DAG. |
| **Log-based metric with label extractors** | Enables Cloud Monitoring to include `dag_id` and `task_id` in alert emails so you know exactly what failed. |
| **`group_by_fields` in aggregation** | Preserves label values through the aggregation pipeline. Without this, labels collapse to `(null)`. |
| **Narrow metric filter** (`textPayload=~"alert_type"`) | Only matches our structured JSON, not random stack traces. Prevents `(null)` labels from non-JSON errors. |
| **Two separate Terraform modules** | Monitoring module is reusable across projects. Deploy simulation once, then point monitoring at any environment. |

### Alert Policies Summary

#### Composer (8 policies)

| # | Policy Name | Source | What It Detects |
|---|---|---|---|
| 1 | Composer - Error Logs Detected ⭐ | Custom log-based metric | Task failures with `dag_id`, `task_id`, `exception` |
| 2 | Composer - Failed DAG Runs | Built-in `workflow/run_count` | Any DAG run with state=failed |
| 3 | Composer - Failed Task Instances | Built-in `finished_task_instance_count` | Any task instance with state=failed |
| 4 | Composer - Database Health Degraded | Built-in `database_health` | Airflow metadata DB unhealthy |
| 5 | Composer - Scheduler Heartbeat Missing | Built-in `scheduler_heartbeat` | Scheduler stopped sending heartbeats |
| 6 | Composer - Worker Pod Evictions | Built-in `worker_pods_evicted` | Kubernetes worker pods evicted |
| 7 | Composer - DAG Parse Errors | Custom log-based metric | Broken DAG files (import errors) |
| 8 | Composer - Webserver Health Degraded | Built-in `webserver_health` | Airflow webserver unhealthy |

#### BigQuery (3 policies)

| # | Policy Name | Source | What It Detects |
|---|---|---|---|
| 1 | BigQuery - High Slot-Time Jobs | Built-in `query/execution_times` | Jobs exceeding slot-time threshold |
| 2 | BigQuery - Scheduled Query Failures | Custom log-based metric | Failed DTS scheduled queries |
| 3 | BigQuery - Data Freshness Stale | Built-in metric (absent condition) | Dataset not receiving new data |

#### Datastream (4 policies, conditional)

| # | Policy Name | Source | What It Detects |
|---|---|---|---|
| 1 | Datastream - Throughput Stale | Built-in metric (absent condition) | Data stopped flowing |
| 2 | Datastream - Stream Unhealthy | Built-in `stream_health` | Stream in error status |
| 3 | Datastream - Backfill Failures | Custom log-based metric | Failed backfill operations |
| 4 | Datastream - High Replication Lag | Built-in `replication_lag` | Lag exceeding threshold (default: 30 min) |

> **Policy #1 (Composer)** is the most useful for debugging — it tells you exactly which DAG and task failed, with the exception message. The Datastream policies are **conditional** — they're only created when `datastream_stream_ids` is non-empty.

---

## Prerequisites

1. **GCP Project** with billing enabled
2. **gcloud CLI** installed and authenticated
3. **Terraform** >= 1.5.0 installed
4. **Permissions**: Composer Admin, Monitoring Admin, Logging Admin, Pub/Sub Admin, BigQuery Admin, Cloud SQL Admin, Datastream Admin, Compute Network Admin

---

## Quick Start

### Step 1: Provision the Simulation Environment

```bash
cd terraform/simulation

# Edit terraform.tfvars — update alert_email and cloudsql_db_password
vim terraform.tfvars

# Initialize and apply
terraform init
terraform plan
terraform apply
```

> **Note:** Cloud Composer takes ~20-25 minutes to provision. Go grab a coffee ☕

After completion, Terraform outputs will include:
- **Airflow UI URL** — bookmark this
- **GCS bucket** — where DAGs are stored
- **Composer environment name** — for DAG deployment
- **Monitoring module inputs** — copy into `terraform/monitoring/terraform.tfvars`

### Step 2: Set Up the Data Pipeline

```bash
# Run the pipeline setup script (builds loadgen, configures Datastream, deploys DAGs)
bash scripts/setup_pipeline.sh
```

This script:
1. Builds and deploys the Go load generator to Cloud Run
2. Configures the PostgreSQL replication slot for Datastream
3. Starts the Datastream CDC stream
4. Deploys DAGs and plugins to Cloud Composer
5. Unpauses the DAGs

### Step 3: Deploy the Monitoring Layer

```bash
cd terraform/monitoring

# Copy values from simulation output (or edit manually)
vim terraform.tfvars

# Initialize and apply
terraform init
terraform plan
terraform apply
```

### Step 4: Verify Pipeline Runs

1. Open the **Airflow UI** (URL from Terraform output)
2. Find the `raw_to_silver` DAG
3. Verify it is **unpaused** and running on schedule (every 15 minutes)
4. Check `silver_to_datamart` is also running (hourly)
5. Watch tasks complete with ✅ green status

### Step 5: Test Failure Alerts 🔥

Fault injection is built directly into the production DAGs (`raw_to_silver`, `silver_to_datamart`, `notebook_executor`), controlled via Airflow Variables:

```bash
# Set environment variables
export GCP_PROJECT_ID="your-project-id"
export COMPOSER_ENV_NAME="monitoring-lab-composer"
export COMPOSER_LOCATION="us-central1"

# Enable chaos with default 30% error rate
gcloud composer environments run $COMPOSER_ENV_NAME \
  --location=$COMPOSER_LOCATION --project=$GCP_PROJECT_ID \
  variables set -- chaos_enabled true

# Trigger the pipeline to see faults in action
gcloud composer environments run $COMPOSER_ENV_NAME \
  --location=$COMPOSER_LOCATION --project=$GCP_PROJECT_ID \
  dags trigger -- raw_to_silver

# Check your email in ~5-10 minutes for alerts:
#   1. "Failed DAG Runs" (built-in metric)
#   2. "Failed Task Instances" (built-in metric)
#   3. "Error Logs Detected" ⭐ (with dag_id, task_id, exception)

# Increase to 100% to guarantee failures for demo
gcloud composer environments run $COMPOSER_ENV_NAME \
  --location=$COMPOSER_LOCATION --project=$GCP_PROJECT_ID \
  variables set -- chaos_error_rate 100

# Turn off after testing
gcloud composer environments run $COMPOSER_ENV_NAME \
  --location=$COMPOSER_LOCATION --project=$GCP_PROJECT_ID \
  variables set -- chaos_enabled false
```

| Variable | Default | What It Does |
|---|---|---|
| `chaos_enabled` | `false` | Master kill switch for all fault injection |
| `chaos_error_rate` | `30` | Probability (0–100%) each injection point fires |
| `chaos_delay_seconds` | `120` | Seconds to sleep for delay injection |

| DAG | Injection Point | Fault Type |
|---|---|---|
| `raw_to_silver` | `chaos_pre_merge` | Delay (simulates slow BigQuery) |
| `raw_to_silver` | `chaos_post_merge` | Failure (simulates post-processing crash) |
| `silver_to_datamart` | `chaos_check` | Failure (simulates aggregation crash) |
| `notebook_executor` | `chaos_<notebook_name>` | Failure (before each notebook execution) |

**After triggering a failure, verify alerts at:**
- 📧 **Email**: Check your inbox (~5-10 min delay)
- 📊 **Cloud Monitoring**: [Alerting Console](https://console.cloud.google.com/monitoring/alerting)
- 📋 **Cloud Logging**: [Logs Explorer](https://console.cloud.google.com/logs)
- 📬 **Pub/Sub**: `gcloud pubsub subscriptions pull composer-alerts-debug-sub --auto-ack --limit=5`

---

## Project Structure

```
da-monitoring-alerting/
├── README.md                              # This file
├── COST_ANALYSIS.md                       # Cost breakdown for monitoring resources
├── DEPLOYMENT_GUIDE.md                    # Full step-by-step deployment guide
│
├── terraform/
│   ├── simulation/                        # Data pipeline infrastructure
│   │   ├── main.tf                        # Provider config + API enablement
│   │   ├── variables.tf                   # Input variables
│   │   ├── terraform.tfvars               # Your configuration values
│   │   ├── composer.tf                    # Cloud Composer 3 (Airflow 2.11.1)
│   │   ├── cloudsql.tf                    # Cloud SQL PostgreSQL 15 (CDC source)
│   │   ├── datastream.tf                  # Datastream CDC (Cloud SQL → BigQuery)
│   │   ├── bigquery.tf                    # BigQuery datasets (raw, silver, datamart)
│   │   ├── cloudrun.tf                    # Cloud Run load generator service
│   │   ├── gcs.tf                         # GCS data lake bucket
│   │   ├── pubsub.tf                      # Pub/Sub topic + debug subscription
│   │   ├── networking.tf                  # VPC, private service connection
│   │   └── outputs.tf                     # Resource names for monitoring module
│   │
│   └── monitoring/                        # ⭐ Reusable monitoring & alerting layer
│       ├── main.tf                        # Provider config + API enablement
│       ├── variables.tf                   # Input variables (service-specific optional)
│       ├── terraform.tfvars               # Your configuration values
│       ├── monitoring_channels.tf         # Email + Slack notification channels
│       ├── monitoring_composer.tf         # 8 Composer alert policies + 2 log-based metrics
│       ├── monitoring_bigquery.tf         # 3 BigQuery alert policies + scheduled queries
│       ├── monitoring_datastream.tf       # 4 Datastream alert policies (conditional)
│       ├── dashboard_composer.tf          # Composer operational health dashboard
│       ├── dashboard_pipeline_health.tf   # Pipeline health dashboard
│       ├── dashboard_cost_storage.tf      # Cost & storage dashboard
│       └── outputs.tf                     # Alert policy names + dashboard IDs
│
├── dags/
│   ├── raw_to_silver.py                   # RAW → SILVER transformation (every 15 min)
│   ├── silver_to_datamart.py              # SILVER → DATAMART aggregation (hourly)
│   ├── chaos_monkey.py                    # Standalone failure generator (paused by default)
│   ├── notebook_executor.py               # ⭐ Generic notebook execution framework (deferrable)
│   └── config/
│       └── notebooks.yaml                 # Notebook registry for notebook_executor
│
├── notebooks/
│   └── orders_report.ipynb                # Orders pipeline report notebook
│
├── plugins/
│   ├── global_failure_listener.py         # ⭐ Global listener — covers ALL DAGs automatically
│   ├── fault_injection.py                 # ⭐ Configurable chaos for production DAGs
│   └── notebook_execution_trigger.py      # Deferrable trigger for Vertex AI notebook execution
│
├── loadgen/
│   ├── main.go                            # Go load generator (inserts/updates orders)
│   ├── Dockerfile                         # Container image for Cloud Run
│   ├── go.mod                             # Go module definition
│   └── go.sum                             # Go dependency checksums
│
├── scripts/
│   ├── deploy_dags.sh                     # Deploy DAGs, plugins, and config to Composer
│   └── setup_pipeline.sh                  # End-to-end pipeline setup (loadgen, Datastream, DAGs)
│
├── tests/
│   ├── test_notebook_executor.py          # Unit tests for notebook executor
│   └── trigger_failures.sh               # Interactive failure trigger
│
└── docs/
    ├── available_gcp_metrics.md           # Full reference of built-in GCP metrics
    ├── composer_monitoring_guide.md       # How Cloud Composer monitoring works
    ├── design_decisions.md                # Key technical decisions and rationale
    └── pipeline_architecture.png          # Architecture diagram
```

---

## Notebook Executor Framework

The `notebook_executor` DAG provides a **generic, deferrable notebook execution framework** that solves three pain points with native BQ Scheduled Notebooks:

| Pain Point | How notebook_executor Solves It |
|---|---|
| No alerting on failure | Runs as Composer tasks → covered by global failure listener → triggers Cloud Monitoring alerts |
| Hard to check logs | Output captured in Airflow UI via XCom — no need to download from GCS |
| Can't rerun with same params | Use Airflow's "Clear task" to rerun any notebook instantly |

### How It Works

1. Register notebooks in `dags/config/notebooks.yaml` — no DAG code changes needed
2. The DAG reads the YAML at parse time and creates a task per notebook
3. Each task submits the notebook to Colab Enterprise / Vertex AI, then **defers** to an async trigger
4. The trigger polls in Airflow's triggerer process — **worker slots are freed** during notebook execution
5. Failures are caught by the global listener and trigger the same alert flow as any other DAG

---

## Scaling to Hundreds of DAGs

You do **NOT** need to add `on_failure_callback` to every DAG manually.

### The Global Listener Plugin

The `plugins/global_failure_listener.py` file uses the **Airflow 2.6+ Listener API** to hook into task lifecycle events globally. It runs on **every task failure across every DAG** automatically — no DAG code changes needed.

```python
from airflow.listeners import hookimpl      # Available since Airflow 2.6
from airflow.plugins_manager import AirflowPlugin

class GlobalFailureListener:
    @hookimpl
    def on_task_instance_failed(self, previous_state, task_instance, error=None, session=None):
        alert = {
            "alert_type": "TASK_FAILURE",
            "dag_id": task_instance.dag_id,
            "task_id": task_instance.task_id,
            "exception": str(error),
            "log_url": task_instance.log_url,
            ...
        }
        log.error(json.dumps(alert))  # → Cloud Logging → Metric → Alert → Email

class GlobalFailureListenerPlugin(AirflowPlugin):
    name = "global_failure_listener"
    listeners = [GlobalFailureListener()]
```

Deploy it once and every DAG — existing and future — is covered:

```bash
gcloud composer environments storage plugins import \
    --environment=YOUR_ENV --location=YOUR_LOCATION \
    --source=plugins/global_failure_listener.py
```

Or just run `bash scripts/deploy_dags.sh` which deploys everything including the plugin.

---

## Key Airflow 2.11.1 / Composer 3 Gotchas

Issues discovered during development and testing:

| Issue | Symptom | Fix |
|---|---|---|
| **`execution_date` deprecated** | DeprecationWarning in logs | Use `logical_date` as primary, `execution_date` as fallback |
| **`schedule_interval` deprecated** | DeprecationWarning | Use `schedule` parameter (supported since Airflow 2.4) |
| **Listener import path** | `ModuleNotFoundError: airflow.listeners.hookimpl` | Use `from airflow.listeners import hookimpl` (works since 2.6) |
| **SLA feature available** | N/A — SLA works in Airflow 2.x | Set `sla=timedelta(...)` on tasks for duration alerts |
| **BQ TIMESTAMP vs DATE** | `No matching signature for operator >=` | Use `TIMESTAMP_SUB(CURRENT_TIMESTAMP(), ...)` not `DATE_SUB(CURRENT_DATE(), ...)` |
| **Context key changes** | `KeyError: 'logical_date'` | Use `context.get('logical_date', context.get('execution_date', ...))` |
| **Composer 3 metric names** | Alert policies not firing | DAG Runs: `workflow/run_count` on `cloud_composer_workflow` resource |
| **Log metric label extraction** | `(null)` in alert emails | Narrow metric filter + add `group_by_fields` to aggregation |

---

## Cleanup

Tear down **everything** in reverse order:

```bash
# 1. Remove monitoring first
cd terraform/monitoring
terraform destroy

# 2. Then remove the simulation environment
cd ../simulation
terraform destroy
```

This removes:
- Cloud Composer environment
- Cloud SQL instance
- Datastream stream and connection profiles
- BigQuery datasets (including all tables)
- Cloud Run load generator service
- All alerting policies and dashboards
- All notification channels
- All log-based metrics and scheduled queries
- Pub/Sub topic and subscription
- GCS buckets
- VPC networking

> **Note:** Composer teardown takes ~15-20 minutes. Cloud SQL and Datastream take ~5-10 minutes.

---

## Additional Documentation

| Document | Description |
|---|---|
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | Full step-by-step deployment guide for a new GCP project |
| [COST_ANALYSIS.md](COST_ANALYSIS.md) | Cost breakdown for the monitoring & alerting layer |
| [docs/available_gcp_metrics.md](docs/available_gcp_metrics.md) | Full reference of built-in GCP metrics for dashboards and alerts |
| [docs/composer_monitoring_guide.md](docs/composer_monitoring_guide.md) | How Cloud Composer monitoring works (global listener + built-in metrics) |
| [docs/design_decisions.md](docs/design_decisions.md) | Key technical decisions and rationale |

---

## Customization Ideas

Once you've completed the lab:

- **Add Slack notifications**: Set `slack_webhook_url` in `terraform/monitoring/terraform.tfvars` and run `terraform apply` — all alerting policies automatically include it
- **Customize dashboards**: Add more widgets or create environment-specific dashboards
- **Add more notebook executions**: Add entries to `dags/config/notebooks.yaml` — no DAG code changes needed
- **Add more runtimes**: Add a Spark task (`DataprocSubmitJobOperator`) or a Cloud Function task
- **Escalation tiers**: Route P0 alerts to PagerDuty and P1 alerts to email
- **SLA Alerts**: Set `sla=timedelta(...)` on tasks for time-sensitive pipelines (available in Airflow 2.x)
- **Add exception details**: Extend the log-based metric with more label extractors (e.g., `exception`, `log_url`)
- **Tune fault injection**: Adjust `chaos_error_rate` to simulate different failure scenarios (e.g., 5% for realistic production, 100% for demos)
- **Add more injection points**: Import `fault_injection` in other DAGs and add `maybe_fail_task` / `maybe_delay_task` / `maybe_corrupt_query` at any point in the task chain
- **Monitor the monitoring module**: Apply the monitoring module to a second project to see how it works as a reusable component
