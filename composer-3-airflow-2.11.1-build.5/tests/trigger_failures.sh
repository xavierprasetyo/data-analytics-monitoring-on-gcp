#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# trigger_failures.sh
#
# Interactive script to toggle failure triggers and test alerting.
# Sets Airflow Variables via the gcloud composer CLI to force task failures.
#
# Prerequisites:
#   - Cloud Composer environment running with the sample DAG deployed
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
DAG_ID="sample_elt_pipeline"

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
    echo ""
    echo "  Triggering DAG run..."
    gcloud composer environments run "${COMPOSER_ENV_NAME}" \
        --location="${COMPOSER_LOCATION}" \
        --project="${GCP_PROJECT_ID}" \
        dags trigger -- "${DAG_ID}" 2>/dev/null
    echo "  ✓ DAG triggered. Check the Airflow UI for progress."
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
echo "============================================="
echo " Failure Trigger Test Menu"
echo " Composer: ${COMPOSER_ENV_NAME}"
echo " DAG: ${DAG_ID}"
echo "============================================="
echo ""
echo "Choose a scenario to test:"
echo ""
echo "  1) Success — Run pipeline with no failures"
echo "  2) Airbyte failure — Force the Airbyte extraction to fail"
echo "  3) dbt failure — Force the dbt transformation to fail"
echo "  4) Both failures — Force Airbyte and dbt to fail"
echo "  5) Reset all — Clear all failure flags"
echo "  6) Check current variables — Show current failure flags"
echo "  7) Trigger DAG run only — Don't change variables, just trigger"
echo "  0) Exit"
echo ""
read -rp "Enter choice [0-7]: " choice

case "${choice}" in
    1)
        echo ""
        echo "Setting all tasks to succeed..."
        set_variable "force_fail_airbyte" "false"
        set_variable "force_fail_dbt" "false"
        trigger_dag
        echo ""
        echo "Expected: All tasks succeed. No failure alerts should fire."
        ;;
    2)
        echo ""
        echo "Setting Airbyte extraction to fail..."
        set_variable "force_fail_airbyte" "true"
        set_variable "force_fail_dbt" "false"
        trigger_dag
        echo ""
        echo "Expected:"
        echo "  - extract_airbyte task fails"
        echo "  - on_failure_callback sends email alert"
        echo "  - Cloud Monitoring fires 'Failed Task Instances' alert"
        echo "  - Downstream tasks are skipped"
        ;;
    3)
        echo ""
        echo "Setting dbt transformation to fail..."
        set_variable "force_fail_airbyte" "false"
        set_variable "force_fail_dbt" "true"
        trigger_dag
        echo ""
        echo "Expected:"
        echo "  - extract_airbyte and load_to_staging_bq succeed"
        echo "  - run_dbt_transform task fails"
        echo "  - on_failure_callback sends email alert"
        echo "  - Cloud Monitoring fires 'Failed Task Instances' alert"
        echo "  - validate_data_bq and notify_success are skipped"
        ;;
    4)
        echo ""
        echo "Setting both Airbyte and dbt to fail..."
        set_variable "force_fail_airbyte" "true"
        set_variable "force_fail_dbt" "true"
        trigger_dag
        echo ""
        echo "Expected:"
        echo "  - extract_airbyte fails immediately"
        echo "  - All downstream tasks are skipped"
        echo "  - on_failure_callback sends email"
        echo "  - DAG-level on_failure_callback fires"
        echo "  - Cloud Monitoring fires alerts for both DAG and task failures"
        ;;
    5)
        echo ""
        echo "Resetting all failure flags..."
        set_variable "force_fail_airbyte" "false"
        set_variable "force_fail_dbt" "false"
        echo ""
        echo "All failure flags cleared. Next DAG run will succeed."
        ;;
    6)
        echo ""
        echo "Current Airflow variables:"
        gcloud composer environments run "${COMPOSER_ENV_NAME}" \
            --location="${COMPOSER_LOCATION}" \
            --project="${GCP_PROJECT_ID}" \
            variables list 2>/dev/null || echo "  (could not retrieve variables)"
        ;;
    7)
        trigger_dag
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
