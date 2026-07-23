#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup_alerting_policies.sh
#
# Creates Cloud Monitoring alerting policies for Cloud Composer.
# These policies monitor infrastructure-level metrics and fire alerts
# when thresholds are breached.
#
# Prerequisites:
#   - Notification channels created (run setup_notification_channels.sh first)
#   - Cloud Composer environment running
#
# Usage:
#   export GCP_PROJECT_ID="your-project-id"
#   export COMPOSER_ENV_NAME="your-composer-env"
#   export COMPOSER_LOCATION="us-central1"
#   bash monitoring/setup_alerting_policies.sh
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
GCP_PROJECT_ID="${GCP_PROJECT_ID:?ERROR: Set GCP_PROJECT_ID environment variable}"
COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:?ERROR: Set COMPOSER_ENV_NAME environment variable}"
COMPOSER_LOCATION="${COMPOSER_LOCATION:-us-central1}"

echo "============================================="
echo " Setting up Alerting Policies"
echo " Project: ${GCP_PROJECT_ID}"
echo " Composer: ${COMPOSER_ENV_NAME} (${COMPOSER_LOCATION})"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# Discover notification channels
# ---------------------------------------------------------------------------
echo "[0/5] Discovering notification channels..."
NOTIFICATION_CHANNELS=$(gcloud monitoring channels list \
    --project="${GCP_PROJECT_ID}" \
    --filter="displayName~'Composer Alerts'" \
    --format="value(name)" | tr '\n' ',' | sed 's/,$//')

if [ -z "${NOTIFICATION_CHANNELS}" ]; then
    echo "       ✗ ERROR: No notification channels found."
    echo "         Run setup_notification_channels.sh first."
    exit 1
fi
echo "       ✓ Found channels: ${NOTIFICATION_CHANNELS}"
echo ""

# ---------------------------------------------------------------------------
# Helper function to create an alerting policy from JSON
# ---------------------------------------------------------------------------
create_policy() {
    local policy_name="$1"
    local policy_file="$2"

    # Check if a policy with this display name already exists
    EXISTING=$(gcloud monitoring policies list \
        --project="${GCP_PROJECT_ID}" \
        --filter="displayName='${policy_name}'" \
        --format="value(name)" 2>/dev/null || true)

    if [ -n "${EXISTING}" ]; then
        echo "       ⚠ Policy '${policy_name}' already exists: ${EXISTING}"
    else
        gcloud monitoring policies create \
            --project="${GCP_PROJECT_ID}" \
            --policy-from-file="${policy_file}" \
            --quiet
        echo "       ✓ Created: ${policy_name}"
    fi
    rm -f "${policy_file}"
}

# ---------------------------------------------------------------------------
# Convert comma-separated channels to JSON array
# ---------------------------------------------------------------------------
CHANNELS_JSON=$(echo "${NOTIFICATION_CHANNELS}" | tr ',' '\n' | awk '{print "\"" $0 "\""}' | paste -sd ',' | sed 's/^/[/;s/$/]/')

# ---------------------------------------------------------------------------
# Policy 1: Failed DAG Runs
# ---------------------------------------------------------------------------
echo "[1/5] Creating policy: Failed DAG Runs..."
POLICY_FILE=$(mktemp)
cat > "${POLICY_FILE}" <<EOF
{
  "displayName": "Composer - Failed DAG Runs",
  "documentation": {
    "content": "A DAG run has failed in Cloud Composer environment '${COMPOSER_ENV_NAME}'. Check the Airflow UI for details.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "DAG run count with state=failed > 0",
      "conditionThreshold": {
        "filter": "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${COMPOSER_ENV_NAME}\" AND metric.type = \"composer.googleapis.com/environment/dagrun/count\" AND metric.labels.state = \"failed\"",
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
create_policy "Composer - Failed DAG Runs" "${POLICY_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Policy 2: Failed Task Instances
# ---------------------------------------------------------------------------
echo "[2/5] Creating policy: Failed Task Instances..."
POLICY_FILE=$(mktemp)
cat > "${POLICY_FILE}" <<EOF
{
  "displayName": "Composer - Failed Task Instances",
  "documentation": {
    "content": "Task instances have failed in Cloud Composer environment '${COMPOSER_ENV_NAME}'. Check the Airflow UI for the failing task details.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Task instance count with state=failed > 0",
      "conditionThreshold": {
        "filter": "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${COMPOSER_ENV_NAME}\" AND metric.type = \"composer.googleapis.com/environment/task/instance_count\" AND metric.labels.state = \"failed\"",
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
create_policy "Composer - Failed Task Instances" "${POLICY_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Policy 3: Scheduler Heartbeat Missing
# ---------------------------------------------------------------------------
echo "[3/5] Creating policy: Scheduler Heartbeat Missing..."
POLICY_FILE=$(mktemp)
cat > "${POLICY_FILE}" <<EOF
{
  "displayName": "Composer - Scheduler Heartbeat Missing",
  "documentation": {
    "content": "The Airflow scheduler in Cloud Composer environment '${COMPOSER_ENV_NAME}' has stopped sending heartbeats. The scheduler may be down or unhealthy.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Scheduler heartbeat absent for 5 minutes",
      "conditionAbsent": {
        "filter": "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${COMPOSER_ENV_NAME}\" AND metric.type = \"composer.googleapis.com/environment/scheduler_heartbeat_count\"",
        "duration": "300s",
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
    "autoClose": "3600s"
  }
}
EOF
create_policy "Composer - Scheduler Heartbeat Missing" "${POLICY_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Policy 4: Worker Pod Evictions
# ---------------------------------------------------------------------------
echo "[4/5] Creating policy: Worker Pod Evictions..."
POLICY_FILE=$(mktemp)
cat > "${POLICY_FILE}" <<EOF
{
  "displayName": "Composer - Worker Pod Evictions",
  "documentation": {
    "content": "Worker pods are being evicted in Cloud Composer environment '${COMPOSER_ENV_NAME}'. This usually indicates resource pressure (memory/CPU). Consider scaling up worker resources.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Worker pod eviction count > 0",
      "conditionThreshold": {
        "filter": "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${COMPOSER_ENV_NAME}\" AND metric.type = \"composer.googleapis.com/environment/worker/pod_eviction_count\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "trigger": {
          "count": 1
        },
        "aggregations": [
          {
            "alignmentPeriod": "900s",
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
    "autoClose": "3600s"
  }
}
EOF
create_policy "Composer - Worker Pod Evictions" "${POLICY_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Policy 5: Database Health Degraded
# ---------------------------------------------------------------------------
echo "[5/5] Creating policy: Database Health Degraded..."
POLICY_FILE=$(mktemp)
cat > "${POLICY_FILE}" <<EOF
{
  "displayName": "Composer - Database Health Degraded",
  "documentation": {
    "content": "The metadata database for Cloud Composer environment '${COMPOSER_ENV_NAME}' is reporting unhealthy status. This can cause DAG processing failures and scheduler issues.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Database health is not healthy",
      "conditionThreshold": {
        "filter": "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${COMPOSER_ENV_NAME}\" AND metric.type = \"composer.googleapis.com/environment/database_health\" AND metric.labels.database_health_state != \"SERVING\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "300s",
        "trigger": {
          "count": 1
        },
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_COUNT"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": ${CHANNELS_JSON},
  "alertStrategy": {
    "autoClose": "3600s"
  }
}
EOF
create_policy "Composer - Database Health Degraded" "${POLICY_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "============================================="
echo " Alerting Policies Setup Complete!"
echo "============================================="
echo ""
echo " Created 5 alerting policies:"
echo "   1. Failed DAG Runs"
echo "   2. Failed Task Instances"
echo "   3. Scheduler Heartbeat Missing"
echo "   4. Worker Pod Evictions"
echo "   5. Database Health Degraded"
echo ""
echo " NEXT STEP: Run setup_log_based_metrics.sh"
echo ""
echo " To list all policies:"
echo "   gcloud monitoring policies list --project=${GCP_PROJECT_ID}"
echo "============================================="
