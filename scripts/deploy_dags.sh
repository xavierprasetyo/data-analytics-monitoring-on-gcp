#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# deploy_dags.sh
#
# Deploys DAG files, scripts, and SQL to the Cloud Composer environment.
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
echo "[1/5] Uploading DAG files..."
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
# 2. Deploy simulation scripts
# ---------------------------------------------------------------------------
echo "[2/5] Uploading simulation scripts..."
for script_file in "${PROJECT_DIR}"/scripts/simulate_*.sh; do
    filename=$(basename "${script_file}")
    gcloud composer environments storage dags import \
        --environment="${COMPOSER_ENV_NAME}" \
        --location="${COMPOSER_LOCATION}" \
        --project="${GCP_PROJECT_ID}" \
        --source="${script_file}" \
        --destination="scripts/" \
        --quiet
    echo "       ✓ scripts/${filename}"
done
echo ""

# ---------------------------------------------------------------------------
# 3. Deploy SQL files
# ---------------------------------------------------------------------------
echo "[3/5] Uploading SQL files..."
for sql_file in "${PROJECT_DIR}"/sql/*.sql; do
    filename=$(basename "${sql_file}")
    gcloud composer environments storage dags import \
        --environment="${COMPOSER_ENV_NAME}" \
        --location="${COMPOSER_LOCATION}" \
        --project="${GCP_PROJECT_ID}" \
        --source="${sql_file}" \
        --destination="sql/" \
        --quiet
    echo "       ✓ sql/${filename}"
done
echo ""

# ---------------------------------------------------------------------------
# 4. Deploy plugins (global listener for ALL DAGs)
# ---------------------------------------------------------------------------
echo "[4/5] Uploading plugins..."
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
# 4. Set Airflow variables
# ---------------------------------------------------------------------------
echo "[5/5] Setting Airflow variables..."
declare -A VARIABLES=(
    ["gcp_project_id"]="${GCP_PROJECT_ID}"
    ["bq_dataset_id"]="monitoring_lab"
    ["force_fail_airbyte"]="false"
    ["force_fail_dbt"]="false"
)

for key in "${!VARIABLES[@]}"; do
    gcloud composer environments run "${COMPOSER_ENV_NAME}" \
        --location="${COMPOSER_LOCATION}" \
        --project="${GCP_PROJECT_ID}" \
        variables set -- "${key}" "${VARIABLES[${key}]}" 2>/dev/null
    echo "       ✓ ${key} = ${VARIABLES[${key}]}"
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
echo "   2. Find the 'sample_elt_pipeline' DAG"
echo "   3. Unpause it (toggle on)"
echo "   4. Trigger a manual run to verify it works"
echo ""
echo " To test failure alerts:"
echo "   bash tests/trigger_failures.sh"
echo "============================================="
