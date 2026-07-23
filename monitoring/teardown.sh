#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# teardown.sh
#
# Removes all monitoring resources created by the setup scripts.
# Use this to clean up after learning or to start fresh.
#
# Usage:
#   export GCP_PROJECT_ID="your-project-id"
#   bash monitoring/teardown.sh
# ---------------------------------------------------------------------------

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:?ERROR: Set GCP_PROJECT_ID environment variable}"

echo "============================================="
echo " Tearing Down Monitoring Resources"
echo " Project: ${GCP_PROJECT_ID}"
echo "============================================="
echo ""
echo "⚠  WARNING: This will delete all Composer monitoring resources."
echo "   Press Ctrl+C within 5 seconds to cancel..."
sleep 5
echo ""

# ---------------------------------------------------------------------------
# 1. Delete alerting policies
# ---------------------------------------------------------------------------
echo "[1/4] Deleting alerting policies..."
POLICIES=$(gcloud monitoring policies list \
    --project="${GCP_PROJECT_ID}" \
    --filter="displayName~'Composer'" \
    --format="value(name)" 2>/dev/null || true)

if [ -z "${POLICIES}" ]; then
    echo "       No Composer alerting policies found."
else
    echo "${POLICIES}" | while read -r policy; do
        gcloud monitoring policies delete "${policy}" \
            --project="${GCP_PROJECT_ID}" --quiet 2>/dev/null || true
        echo "       ✓ Deleted: ${policy}"
    done
fi
echo ""

# ---------------------------------------------------------------------------
# 2. Delete notification channels
# ---------------------------------------------------------------------------
echo "[2/4] Deleting notification channels..."
CHANNELS=$(gcloud monitoring channels list \
    --project="${GCP_PROJECT_ID}" \
    --filter="displayName~'Composer Alerts'" \
    --format="value(name)" 2>/dev/null || true)

if [ -z "${CHANNELS}" ]; then
    echo "       No Composer notification channels found."
else
    echo "${CHANNELS}" | while read -r channel; do
        gcloud monitoring channels delete "${channel}" \
            --project="${GCP_PROJECT_ID}" --force --quiet 2>/dev/null || true
        echo "       ✓ Deleted: ${channel}"
    done
fi
echo ""

# ---------------------------------------------------------------------------
# 3. Delete log-based metrics
# ---------------------------------------------------------------------------
echo "[3/4] Deleting log-based metrics..."
for metric in composer_task_errors composer_dag_parse_errors; do
    if gcloud logging metrics describe "${metric}" \
        --project="${GCP_PROJECT_ID}" &>/dev/null; then
        gcloud logging metrics delete "${metric}" \
            --project="${GCP_PROJECT_ID}" --quiet
        echo "       ✓ Deleted metric: ${metric}"
    else
        echo "       Metric '${metric}' not found (already deleted)."
    fi
done
echo ""

# ---------------------------------------------------------------------------
# 4. Delete Pub/Sub resources
# ---------------------------------------------------------------------------
echo "[4/4] Deleting Pub/Sub resources..."
SUB_NAME="composer-alerts-debug-sub"
TOPIC_NAME="composer-alerts"

if gcloud pubsub subscriptions describe "${SUB_NAME}" \
    --project="${GCP_PROJECT_ID}" &>/dev/null; then
    gcloud pubsub subscriptions delete "${SUB_NAME}" \
        --project="${GCP_PROJECT_ID}" --quiet
    echo "       ✓ Deleted subscription: ${SUB_NAME}"
else
    echo "       Subscription '${SUB_NAME}' not found."
fi

if gcloud pubsub topics describe "${TOPIC_NAME}" \
    --project="${GCP_PROJECT_ID}" &>/dev/null; then
    gcloud pubsub topics delete "${TOPIC_NAME}" \
        --project="${GCP_PROJECT_ID}" --quiet
    echo "       ✓ Deleted topic: ${TOPIC_NAME}"
else
    echo "       Topic '${TOPIC_NAME}' not found."
fi
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "============================================="
echo " Teardown Complete!"
echo "============================================="
echo ""
echo " All Composer monitoring resources have been removed."
echo " To also clean up the BigQuery dataset:"
echo "   bq rm -r -f ${GCP_PROJECT_ID}:monitoring_lab"
echo ""
echo " To delete the DAG from Composer:"
echo "   gcloud composer environments storage dags delete \\"
echo "     sample_elt_pipeline.py --environment=YOUR_ENV \\"
echo "     --location=YOUR_LOCATION"
echo "============================================="
