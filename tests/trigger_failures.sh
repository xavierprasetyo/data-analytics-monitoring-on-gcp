#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# trigger_failures.sh
#
# Interactive script to toggle chaos injection and test alerting.
# Controls the fault injection built into raw_to_silver and
# silver_to_datamart DAGs via Airflow Variables.
#
# Prerequisites:
#   - Cloud Composer environment running with DAGs deployed
#   - gcloud CLI authenticated
#
# Usage:
#   export GCP_PROJECT_ID="your-project-id"
#   export COMPOSER_ENV_NAME="your-composer-env"
#   export COMPOSER_LOCATION="us-central1"
#   bash tests/trigger_failures.sh
# ---------------------------------------------------------------------------

set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:?ERROR: Set GCP_PROJECT_ID environment variable}"
COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:?ERROR: Set COMPOSER_ENV_NAME environment variable}"
COMPOSER_LOCATION="${COMPOSER_LOCATION:-us-central1}"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
set_variable() {
    local key="$1"
    local value="$2"
    gcloud composer environments run "${COMPOSER_ENV_NAME}" \
        --location="${COMPOSER_LOCATION}" \
        --project="${GCP_PROJECT_ID}" \
        variables set -- "${key}" "${value}" 2>/dev/null
    echo "  ✓ Set ${key} = ${value}"
}

trigger_dag() {
    local dag_id="$1"
    echo ""
    echo "  Triggering DAG run: ${dag_id}..."
    gcloud composer environments run "${COMPOSER_ENV_NAME}" \
        --location="${COMPOSER_LOCATION}" \
        --project="${GCP_PROJECT_ID}" \
        dags trigger -- "${dag_id}" 2>/dev/null
    echo "  ✓ DAG ${dag_id} triggered. Check the Airflow UI for progress."
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
echo "============================================="
echo " Failure Trigger Test Menu"
echo " Composer: ${COMPOSER_ENV_NAME}"
echo " DAGs: raw_to_silver, silver_to_datamart"
echo "============================================="
echo ""
echo "Choose a scenario to test:"
echo ""
echo "  1) Enable chaos (30% error rate) — turn on fault injection"
echo "  2) Enable chaos (100% error rate) — guarantee failures for demo"
echo "  3) Trigger raw_to_silver — run the RAW → SILVER pipeline"
echo "  4) Trigger silver_to_datamart — run the SILVER → DATAMART pipeline"
echo "  5) Trigger both pipelines"
echo "  6) Adjust delay — set chaos delay seconds"
echo "  7) Disable chaos — turn off all fault injection"
echo "  8) Check current variables — show chaos settings"
echo "  0) Exit"
echo ""
read -rp "Enter choice [0-8]: " choice

case "${choice}" in
    1)
        echo ""
        echo "Enabling chaos injection at 30% error rate..."
        set_variable "chaos_enabled" "true"
        set_variable "chaos_error_rate" "30"
        echo ""
        echo "Chaos enabled. Injection points:"
        echo "  - raw_to_silver: chaos_pre_merge (delay), chaos_post_merge (failure)"
        echo "  - silver_to_datamart: chaos_check (failure)"
        echo ""
        echo "Trigger a DAG run to see faults in action (options 3-5)."
        ;;
    2)
        echo ""
        echo "Enabling chaos injection at 100% error rate..."
        set_variable "chaos_enabled" "true"
        set_variable "chaos_error_rate" "100"
        echo ""
        echo "Chaos enabled at 100% — every injection point WILL fire."
        echo "Trigger a DAG run to see faults in action (options 3-5)."
        ;;
    3)
        trigger_dag "raw_to_silver"
        echo ""
        echo "Expected (if chaos enabled):"
        echo "  - chaos_pre_merge: may inject delay before MERGE"
        echo "  - chaos_post_merge: may fail after MERGE"
        echo "  - Global listener emits structured error log"
        echo "  - Cloud Monitoring fires 'Error Logs Detected' alert"
        ;;
    4)
        trigger_dag "silver_to_datamart"
        echo ""
        echo "Expected (if chaos enabled):"
        echo "  - chaos_check: may fail before aggregation queries"
        echo "  - Global listener emits structured error log"
        echo "  - Cloud Monitoring fires 'Error Logs Detected' alert"
        ;;
    5)
        trigger_dag "raw_to_silver"
        trigger_dag "silver_to_datamart"
        echo ""
        echo "Both pipelines triggered."
        ;;
    6)
        read -rp "Enter delay seconds (default 120): " delay
        delay="${delay:-120}"
        set_variable "chaos_delay_seconds" "${delay}"
        echo ""
        echo "Delay injection set to ${delay} seconds."
        ;;
    7)
        echo ""
        echo "Disabling chaos injection..."
        set_variable "chaos_enabled" "false"
        echo ""
        echo "Chaos disabled. All DAG runs will succeed normally."
        ;;
    8)
        echo ""
        echo "Current Airflow variables:"
        gcloud composer environments run "${COMPOSER_ENV_NAME}" \
            --location="${COMPOSER_LOCATION}" \
            --project="${GCP_PROJECT_ID}" \
            variables list 2>/dev/null || echo "  (could not retrieve variables)"
        ;;
    0)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "============================================="
echo " Useful commands for verifying alerts:"
echo "============================================="
echo ""
echo " Check Airflow UI:"
echo "   gcloud composer environments describe ${COMPOSER_ENV_NAME} \\"
echo "     --location=${COMPOSER_LOCATION} --format='value(config.airflowUri)'"
echo ""
echo " Check Cloud Monitoring incidents:"
echo "   gcloud monitoring policies list --project=${GCP_PROJECT_ID} \\"
echo "     --filter=\"displayName~'Composer'\""
echo ""
echo " Check Pub/Sub messages:"
echo "   gcloud pubsub subscriptions pull composer-alerts-debug-sub \\"
echo "     --project=${GCP_PROJECT_ID} --auto-ack --limit=5"
echo ""
echo " Check Cloud Logging:"
echo "   gcloud logging read 'resource.type=\"cloud_composer_environment\" severity>=ERROR' \\"
echo "     --project=${GCP_PROJECT_ID} --limit=5 --format=json"
echo "============================================="
