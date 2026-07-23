#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup_log_based_metrics.sh
#
# Creates log-based metrics and alerting policies in Cloud Logging
# to catch errors from all runtimes (Spark, BigQuery, dbt, Airbyte, etc.)
# that flow through Airflow's logs.
#
# Prerequisites:
#   - Notification channels created (run setup_notification_channels.sh first)
#   - Cloud Composer environment running
#
# Usage:
#   export GCP_PROJECT_ID="your-project-id"
#   export COMPOSER_ENV_NAME="your-composer-env"
#   bash monitoring/setup_log_based_metrics.sh
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
GCP_PROJECT_ID="${GCP_PROJECT_ID:?ERROR: Set GCP_PROJECT_ID environment variable}"
COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:?ERROR: Set COMPOSER_ENV_NAME environment variable}"

echo "============================================="
echo " Setting up Log-Based Metrics & Alerts"
echo " Project: ${GCP_PROJECT_ID}"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# 1. Create log-based metric: Composer Task Errors
# ---------------------------------------------------------------------------
echo "[1/3] Creating log-based metric: composer_task_errors..."

EXISTING_METRIC=$(gcloud logging metrics describe composer_task_errors \
    --project="${GCP_PROJECT_ID}" 2>/dev/null && echo "exists" || echo "")

if [ -n "${EXISTING_METRIC}" ]; then
    echo "       ⚠ Metric 'composer_task_errors' already exists. Updating..."
    gcloud logging metrics update composer_task_errors \
        --project="${GCP_PROJECT_ID}" \
        --description="Error-level logs from Cloud Composer tasks" \
        --log-filter="resource.type=\"cloud_composer_environment\"
resource.labels.environment_name=\"${COMPOSER_ENV_NAME}\"
severity>=ERROR"
else
    gcloud logging metrics create composer_task_errors \
        --project="${GCP_PROJECT_ID}" \
        --description="Error-level logs from Cloud Composer tasks" \
        --log-filter="resource.type=\"cloud_composer_environment\"
resource.labels.environment_name=\"${COMPOSER_ENV_NAME}\"
severity>=ERROR"
fi
echo "       ✓ Log-based metric 'composer_task_errors' configured"
echo ""

# ---------------------------------------------------------------------------
# 2. Create log-based metric: Composer DAG Parse Errors
# ---------------------------------------------------------------------------
echo "[2/3] Creating log-based metric: composer_dag_parse_errors..."

EXISTING_METRIC=$(gcloud logging metrics describe composer_dag_parse_errors \
    --project="${GCP_PROJECT_ID}" 2>/dev/null && echo "exists" || echo "")

if [ -n "${EXISTING_METRIC}" ]; then
    echo "       ⚠ Metric 'composer_dag_parse_errors' already exists. Updating..."
    gcloud logging metrics update composer_dag_parse_errors \
        --project="${GCP_PROJECT_ID}" \
        --description="DAG parsing errors in Cloud Composer" \
        --log-filter="resource.type=\"cloud_composer_environment\"
resource.labels.environment_name=\"${COMPOSER_ENV_NAME}\"
severity>=ERROR
textPayload=~\"DagFileProcessorProcess|DagBag|import_errors\""
else
    gcloud logging metrics create composer_dag_parse_errors \
        --project="${GCP_PROJECT_ID}" \
        --description="DAG parsing errors in Cloud Composer" \
        --log-filter="resource.type=\"cloud_composer_environment\"
resource.labels.environment_name=\"${COMPOSER_ENV_NAME}\"
severity>=ERROR
textPayload=~\"DagFileProcessorProcess|DagBag|import_errors\""
fi
echo "       ✓ Log-based metric 'composer_dag_parse_errors' configured"
echo ""

# ---------------------------------------------------------------------------
# 3. Create alerting policy on the log-based metrics
# ---------------------------------------------------------------------------
echo "[3/3] Creating alerting policy for log-based metrics..."

# Discover notification channels
NOTIFICATION_CHANNELS=$(gcloud monitoring channels list \
    --project="${GCP_PROJECT_ID}" \
    --filter="displayName~'Composer Alerts'" \
    --format="value(name)" | tr '\n' ',' | sed 's/,$//')

CHANNELS_JSON=$(echo "${NOTIFICATION_CHANNELS}" | tr ',' '\n' | awk '{print "\"" $0 "\""}' | paste -sd ',' | sed 's/^/[/;s/$/]/')

# Policy for task errors
POLICY_FILE=$(mktemp)
cat > "${POLICY_FILE}" <<EOF
{
  "displayName": "Composer - Error Logs Detected",
  "documentation": {
    "content": "Error-level logs have been detected in Cloud Composer environment '${COMPOSER_ENV_NAME}'. Check Cloud Logging for details:\n\nhttps://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_composer_environment%22%20severity%3E%3DERROR",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Error log count > 5 in 5 minutes",
      "conditionThreshold": {
        "filter": "resource.type = \"cloud_composer_environment\" AND metric.type = \"logging.googleapis.com/user/composer_task_errors\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 5,
        "duration": "0s",
        "trigger": {
          "count": 1
        },
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_SUM"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": ${CHANNELS_JSON},
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF

EXISTING=$(gcloud monitoring policies list \
    --project="${GCP_PROJECT_ID}" \
    --filter="displayName='Composer - Error Logs Detected'" \
    --format="value(name)" 2>/dev/null || true)

if [ -n "${EXISTING}" ]; then
    echo "       ⚠ Policy 'Composer - Error Logs Detected' already exists"
else
    gcloud monitoring policies create \
        --project="${GCP_PROJECT_ID}" \
        --policy-from-file="${POLICY_FILE}" \
        --quiet
    echo "       ✓ Created: Composer - Error Logs Detected"
fi
rm -f "${POLICY_FILE}"

# Policy for DAG parse errors
POLICY_FILE=$(mktemp)
cat > "${POLICY_FILE}" <<EOF
{
  "displayName": "Composer - DAG Parse Errors",
  "documentation": {
    "content": "DAG parsing errors have been detected in Cloud Composer environment '${COMPOSER_ENV_NAME}'. A DAG file may have syntax errors or missing dependencies.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "DAG parse error count > 0",
      "conditionThreshold": {
        "filter": "resource.type = \"cloud_composer_environment\" AND metric.type = \"logging.googleapis.com/user/composer_dag_parse_errors\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "trigger": {
          "count": 1
        },
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_SUM"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": ${CHANNELS_JSON},
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF

EXISTING=$(gcloud monitoring policies list \
    --project="${GCP_PROJECT_ID}" \
    --filter="displayName='Composer - DAG Parse Errors'" \
    --format="value(name)" 2>/dev/null || true)

if [ -n "${EXISTING}" ]; then
    echo "       ⚠ Policy 'Composer - DAG Parse Errors' already exists"
else
    gcloud monitoring policies create \
        --project="${GCP_PROJECT_ID}" \
        --policy-from-file="${POLICY_FILE}" \
        --quiet
    echo "       ✓ Created: Composer - DAG Parse Errors"
fi
rm -f "${POLICY_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "============================================="
echo " Log-Based Metrics & Alerts Setup Complete!"
echo "============================================="
echo ""
echo " Created 2 log-based metrics:"
echo "   1. composer_task_errors — catches ERROR+ severity logs"
echo "   2. composer_dag_parse_errors — catches DAG parsing errors"
echo ""
echo " Created 2 alerting policies:"
echo "   1. Error Logs Detected — fires when > 5 errors in 5 minutes"
echo "   2. DAG Parse Errors — fires on any parse error"
echo ""
echo " To view metrics:"
echo "   gcloud logging metrics list --project=${GCP_PROJECT_ID}"
echo ""
echo " To view logs:"
echo "   gcloud logging read 'resource.type=\"cloud_composer_environment\" severity>=ERROR' \\"
echo "     --project=${GCP_PROJECT_ID} --limit=10 --format=json"
echo "============================================="
