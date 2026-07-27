#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# deploy_dags.sh
#
# Deploys DAG files and plugins to the Cloud Composer environment.
# Run this after `terraform apply` has completed.
#
# Usage:
#   # Option 1: Set env vars manually
#   export GCP_PROJECT_ID="your-project-id"
#   export COMPOSER_ENV_NAME="monitoring-lab-composer"
#   export COMPOSER_LOCATION="us-central1"
#   bash scripts/deploy_dags.sh
#
#   # Option 2: Auto-detect from Terraform state
#   bash scripts/deploy_dags.sh --from-terraform
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# ---------------------------------------------------------------------------
# Auto-detect from Terraform if --from-terraform flag is passed
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--from-terraform" ]]; then
    echo "Reading configuration from Terraform state..."
    cd "${PROJECT_DIR}/terraform"
    GCP_PROJECT_ID=$(terraform output -raw composer_env_name 2>/dev/null | head -1 || true)
    # Fall back to tfvars
    if [ -z "${GCP_PROJECT_ID:-}" ]; then
        GCP_PROJECT_ID=$(grep 'project_id' terraform.tfvars | cut -d'"' -f2)
    fi
    COMPOSER_ENV_NAME=$(grep 'composer_env_name' terraform.tfvars | cut -d'"' -f2 || echo "monitoring-lab-composer")
    COMPOSER_LOCATION=$(grep 'region' terraform.tfvars | cut -d'"' -f2 || echo "us-central1")
    cd "${PROJECT_DIR}"
fi

GCP_PROJECT_ID="${GCP_PROJECT_ID:?ERROR: Set GCP_PROJECT_ID or use --from-terraform}"
COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:?ERROR: Set COMPOSER_ENV_NAME or use --from-terraform}"
COMPOSER_LOCATION="${COMPOSER_LOCATION:-us-central1}"

echo "============================================="
echo " Deploying DAGs to Cloud Composer"
echo " Project: ${GCP_PROJECT_ID}"
echo " Composer: ${COMPOSER_ENV_NAME} (${COMPOSER_LOCATION})"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# 1. Deploy DAG Python files
# ---------------------------------------------------------------------------
echo "[1/4] Uploading DAG files..."
for dag_file in "${PROJECT_DIR}"/dags/*.py; do
    filename=$(basename "${dag_file}")
    gcloud composer environments storage dags import \
        --environment="${COMPOSER_ENV_NAME}" \
        --location="${COMPOSER_LOCATION}" \
        --project="${GCP_PROJECT_ID}" \
        --source="${dag_file}" \
        --quiet
    echo "       ✓ ${filename}"
done
echo ""

# ---------------------------------------------------------------------------
# 2. Deploy DAG config files
# ---------------------------------------------------------------------------
echo "[2/4] Uploading DAG config files..."
for config_file in "${PROJECT_DIR}"/dags/config/*.yaml; do
    if [ -f "${config_file}" ]; then
        filename=$(basename "${config_file}")
        gcloud composer environments storage dags import \
            --environment="${COMPOSER_ENV_NAME}" \
            --location="${COMPOSER_LOCATION}" \
            --project="${GCP_PROJECT_ID}" \
            --source="${config_file}" \
            --destination="config/" \
            --quiet
        echo "       ✓ config/${filename}"
    fi
done
echo ""

# ---------------------------------------------------------------------------
# 3. Deploy plugins (global listener for ALL DAGs)
# ---------------------------------------------------------------------------
echo "[3/4] Uploading plugins..."
for plugin_file in "${PROJECT_DIR}"/plugins/*.py; do
    if [ -f "${plugin_file}" ]; then
        filename=$(basename "${plugin_file}")
        gcloud composer environments storage plugins import \
            --environment="${COMPOSER_ENV_NAME}" \
            --location="${COMPOSER_LOCATION}" \
            --project="${GCP_PROJECT_ID}" \
            --source="${plugin_file}" \
            --quiet
        echo "       ✓ plugins/${filename}"
    fi
done
echo ""

# ---------------------------------------------------------------------------
# 4. Upload notebooks to GCS bucket
# ---------------------------------------------------------------------------
NOTEBOOKS_BUCKET="${GCP_PROJECT_ID}-monitoring-lab-notebooks"
echo "[4/4] Uploading notebooks to gs://${NOTEBOOKS_BUCKET}/..."
for notebook_file in "${PROJECT_DIR}"/notebooks/*.ipynb; do
    if [ -f "${notebook_file}" ]; then
        filename=$(basename "${notebook_file}")
        gsutil cp "${notebook_file}" "gs://${NOTEBOOKS_BUCKET}/${filename}" 2>&1
        echo "       ✓ ${filename}"
    fi
done
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
AIRFLOW_URI=$(gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
    --location="${COMPOSER_LOCATION}" \
    --project="${GCP_PROJECT_ID}" \
    --format='value(config.airflowUri)' 2>/dev/null || echo "Unable to retrieve")

echo "============================================="
echo " Deployment Complete!"
echo "============================================="
echo ""
echo " Airflow UI: ${AIRFLOW_URI}"
echo ""
echo " NEXT STEPS:"
echo "   1. Open the Airflow UI link above"
echo "   2. Find the 'raw_to_silver' DAG"
echo "   3. Verify it is unpaused and running on schedule (every 15 min)"
echo "   4. To test failure alerts, enable chaos injection:"
echo "      gcloud composer environments run ${COMPOSER_ENV_NAME} \\"
echo "        --location=${COMPOSER_LOCATION} --project=${GCP_PROJECT_ID} \\"
echo "        variables set -- chaos_enabled true"
echo ""
echo " To run the interactive failure test menu:"
echo "   bash tests/trigger_failures.sh"
echo "============================================="
