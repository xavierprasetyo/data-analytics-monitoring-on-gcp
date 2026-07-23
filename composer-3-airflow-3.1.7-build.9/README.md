# Cloud Composer Monitoring & Alerting — Learning Lab

A hands-on project to learn how to set up native GCP monitoring and alerting for Cloud Composer 3 (managed Airflow 3) pipelines. All infrastructure is managed with **Terraform** — one `terraform apply` to set up, one `terraform destroy` to tear down.

## What You'll Build

A sample ELT pipeline with **5 tasks across 3 runtimes**, wired up with **centralized alerting** that automatically covers **every DAG** without per-DAG callbacks:

```
+--------------+    +-------------------+    +------------------+    +------------------+    +----------------+
|   Airbyte    |--->|  BigQuery Staging |--->|  dbt Transform   |--->|  BQ Validation   |--->|    Success     |
| (simulated)  |    |   (real query)    |    |   (simulated)    |    |  (real ASSERT)   |    |  Notification  |
+--------------+    +-------------------+    +------------------+    +------------------+    +----------------+
```

### Infrastructure Created by Terraform

| Resource | What It Does |
|---|---|
| Cloud Composer 3 | Managed Airflow 3.1.7 environment |
| BigQuery Dataset | `monitoring_lab` for pipeline data |
| Pub/Sub Topic + Subscription | Programmatic alert forwarding |
| Email Notification Channel | Email alerts to your inbox |
| 7 Alerting Policies | Monitors DAG failures, task failures, scheduler health, worker evictions, database health, error logs, DAG parse errors |
| 2 Log-based Metrics | Counts structured task errors and DAG parse errors |

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
                                    |    "dag_id": "sample_elt_pipeline",
                                    |    "task_id": "run_dbt_transform",
                                    |    "exception": "exit code 1",
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

### Alert Policies Summary

| # | Policy Name | Source | What It Detects |
|---|---|---|---|
| 1 | Composer - Error Logs Detected ⭐ | Custom log-based metric | Task failures with `dag_id`, `task_id`, `exception` |
| 2 | Composer - Failed DAG Runs | Built-in `workflow/run_count` | Any DAG run with state=failed |
| 3 | Composer - Failed Task Instances | Built-in `finished_task_instance_count` | Any task instance with state=failed |
| 4 | Composer - Database Health Degraded | Built-in `database_health` | Airflow metadata DB unhealthy |
| 5 | Composer - Scheduler Heartbeat Missing | Built-in `scheduler_heartbeat` | Scheduler stopped sending heartbeats |
| 6 | Composer - Worker Pod Evictions | Built-in `worker_pods_evicted` | Kubernetes worker pods evicted |
| 7 | Composer - DAG Parse Errors | Custom log-based metric | Broken DAG files (import errors) |

> **Policy #1** is the most useful for debugging — it tells you exactly which DAG and task failed, with the exception message. Policies #2-#3 are broader "something failed" alerts. Policies #4-#7 cover infrastructure health.

---

## Prerequisites

1. **GCP Project** with billing enabled
2. **gcloud CLI** installed and authenticated
3. **Terraform** >= 1.5.0 installed
4. **Permissions**: Composer Admin, Monitoring Admin, Logging Admin, Pub/Sub Admin, BigQuery Admin

---

## Quick Start

### Step 1: Configure

```bash
cd terraform

# Edit terraform.tfvars — update alert_email with your email
vim terraform.tfvars
```

The only value you **must** change is `alert_email`. Optionally set `slack_webhook_url` to enable Slack alerts.

### Step 2: Provision Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Preview what will be created
terraform plan

# Create everything (~25 minutes for Composer)
terraform apply
```

> **Note:** Cloud Composer takes ~20-25 minutes to provision. Go grab a coffee ☕

After completion, Terraform will output:
- **Airflow UI URL** — bookmark this
- **GCS bucket** — where DAGs are stored
- **All alerting policy names** — verify in Cloud Monitoring console

### Step 3: Deploy DAGs

```bash
# Set environment variables
export GCP_PROJECT_ID="project-sandbox-357505"
export COMPOSER_ENV_NAME="monitoring-lab-composer"
export COMPOSER_LOCATION="us-central1"

# Deploy DAGs, scripts, SQL, plugins, and set Airflow variables
bash scripts/deploy_dags.sh
```

### Step 4: Test a Successful Run

1. Open the **Airflow UI** (URL from Terraform output)
2. Find the `sample_elt_pipeline` DAG
3. **Unpause** it (toggle on)
4. Click **Trigger DAG** to start a manual run
5. Watch all 5 tasks complete with ✅ green status

### Step 5: Test Failure Alerts 🔥

```bash
# Force the dbt task to fail
gcloud composer environments run $COMPOSER_ENV_NAME \
  --location=$COMPOSER_LOCATION --project=$GCP_PROJECT_ID \
  variables set -- force_fail_dbt true

# Trigger the pipeline
gcloud composer environments run $COMPOSER_ENV_NAME \
  --location=$COMPOSER_LOCATION --project=$GCP_PROJECT_ID \
  dags trigger -- sample_elt_pipeline

# Check your email in ~5-10 minutes for 3 alerts:
#   1. "Failed DAG Runs" (built-in metric)
#   2. "Failed Task Instances" (built-in metric)
#   3. "Error Logs Detected" ⭐ (with dag_id, task_id, exception)

# Reset after testing
gcloud composer environments run $COMPOSER_ENV_NAME \
  --location=$COMPOSER_LOCATION --project=$GCP_PROJECT_ID \
  variables set -- force_fail_dbt false
```

| Variable | What It Does |
|---|---|
| `force_fail_airbyte=true` | Makes `extract_airbyte` task fail |
| `force_fail_dbt=true` | Makes `run_dbt_transform` task fail |

**After triggering a failure, verify alerts at:**
- 📧 **Email**: Check your inbox (~5-10 min delay)
- 📊 **Cloud Monitoring**: [Alerting Console](https://console.cloud.google.com/monitoring/alerting?project=project-sandbox-357505)
- 📋 **Cloud Logging**: [Logs Explorer](https://console.cloud.google.com/logs?project=project-sandbox-357505)
- 📬 **Pub/Sub**: `gcloud pubsub subscriptions pull composer-alerts-debug-sub --project=project-sandbox-357505 --auto-ack --limit=5`

---

## Project Structure

```
da-monitoring-alerting/
├── README.md                          # This file
├── terraform/
│   ├── main.tf                        # Provider config + API enablement
│   ├── variables.tf                   # Input variables
│   ├── terraform.tfvars               # Your configuration values
│   ├── composer.tf                    # Cloud Composer 3 environment
│   ├── bigquery.tf                    # BigQuery dataset
│   ├── monitoring.tf                  # Notification channels + 5 alerting policies
│   ├── logging.tf                     # 2 log-based metrics + 2 alerting policies
│   ├── pubsub.tf                      # Pub/Sub topic + debug subscription
│   └── outputs.tf                     # Useful outputs
├── dags/
│   ├── sample_elt_pipeline.py         # Main DAG with 5 tasks
│   └── callbacks.py                   # Shared alerting callbacks (for this sample DAG)
├── plugins/
│   └── global_failure_listener.py     # ⭐ Global listener — covers ALL DAGs automatically
├── scripts/
│   ├── deploy_dags.sh                 # Deploy DAGs, plugins, and config to Composer
│   ├── simulate_airbyte_sync.sh       # Simulated Airbyte extraction
│   └── simulate_dbt_run.sh            # Simulated dbt transformation
├── sql/
│   ├── load_staging.sql               # BQ: load from Stack Overflow public dataset
│   └── validate_data.sql              # BQ: data quality checks (row count, NULL checks)
├── monitoring/                        # Shell script reference (alternative to Terraform)
│   ├── setup_notification_channels.sh
│   ├── setup_alerting_policies.sh
│   ├── setup_log_based_metrics.sh
│   └── teardown.sh
└── tests/
    └── trigger_failures.sh            # Interactive failure trigger
```

---

## Scaling to Hundreds of DAGs

You do **NOT** need to add `on_failure_callback` to every DAG manually.

### The Global Listener Plugin

The `plugins/global_failure_listener.py` file uses the **Airflow 3 Listener API** to hook into task lifecycle events globally. It runs on **every task failure across every DAG** automatically — no DAG code changes needed.

```python
from airflow.listeners import hookimpl      # Airflow 3.1 import path
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

## Key Airflow 3 / Composer 3 Gotchas

Issues discovered during development and testing:

| Issue | Symptom | Fix |
|---|---|---|
| **Listener import path** | `ModuleNotFoundError: airflow.listeners.hookimpl` | Use `from airflow.listeners import hookimpl` (not submodule) |
| **BashOperator template rendering** | `TemplateNotFound: 'bash /path/script.sh'` | Add trailing space: `bash_command="bash /path/script.sh "` |
| **BQ TIMESTAMP vs DATE** | `No matching signature for operator >=` | Use `TIMESTAMP_SUB(CURRENT_TIMESTAMP(), ...)` not `DATE_SUB(CURRENT_DATE(), ...)` |
| **Context key changes** | `KeyError: 'logical_date'` | Use `context.get('logical_date', ...)` with fallbacks |
| **Composer 3 metric names** | Alert policies not firing | DAG Runs: `workflow/run_count` on `cloud_composer_workflow` resource |
| **SQL read at parse time** | SQL changes not picked up | `Path().read_text()` runs at DAG parse time; bump DAG version to force re-parse |
| **Log metric label extraction** | `(null)` in alert emails | Narrow metric filter + add `group_by_fields` to aggregation |
| **SO public dataset frozen** | 0 rows loaded | Data ends Sept 2022; removed date filter |

---

## Cleanup

Tear down **everything** with one command:

```bash
cd terraform
terraform destroy
```

This removes:
- Cloud Composer environment
- BigQuery dataset (including all tables)
- All alerting policies
- All notification channels
- All log-based metrics
- Pub/Sub topic and subscription

> **Note:** Composer teardown also takes ~15-20 minutes.

---

## Customization Ideas

Once you've completed the lab:

- **Add Slack notifications**: Set `slack_webhook_url` in `terraform.tfvars` and run `terraform apply` — all 7 alerting policies automatically include it
- **Build a dashboard**: Create a custom Cloud Monitoring dashboard with Composer metrics
- **Add more runtimes**: Add a Spark task (`DataprocSubmitJobOperator`) or a Cloud Function task
- **Escalation tiers**: Route P0 alerts to PagerDuty and P1 alerts to email
- **Deadline Alerts**: Configure Airflow 3 Deadline Alerts for time-sensitive pipelines
- **Add exception details**: Extend the log-based metric with more label extractors (e.g., `exception`, `log_url`)
