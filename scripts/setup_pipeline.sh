#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup_pipeline.sh — End-to-end pipeline setup script
#
# This script:
#   1. Provisions Cloud Run infra (VPC connector, Artifact Registry)
#   2. Builds and deploys the Go load generator to Cloud Run
#   3. Sets up the PostgreSQL replication slot for Datastream
#   4. Starts the Datastream stream
#   5. Deploys DAGs to Cloud Composer
#   6. Unpauses DAGs
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Configuration (from terraform outputs) ---
PROJECT_ID="${PROJECT_ID:-da-monitoring-lab-07230757}"
REGION="${REGION:-us-central1}"
CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE:-monitoring-lab-source-pg}"
DB_NAME="${DB_NAME:-source_db}"
DB_USER="${DB_USER:-datastream_user}"
DB_PASS="${DB_PASS:-datastream-lab-2026}"
DATASTREAM_STREAM="${DATASTREAM_STREAM:-monitoring-lab-stream}"
COMPOSER_ENV="${COMPOSER_ENV:-monitoring-lab-composer}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "  DA Monitoring Lab — Pipeline Setup"
echo "============================================"
echo "Project:    $PROJECT_ID"
echo "Region:     $REGION"
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Provision Cloud Run infrastructure via Terraform
# ---------------------------------------------------------------------------
step_terraform() {
    echo ">>> Step 1: Provisioning Cloud Run infrastructure..."

    cd "$PROJECT_ROOT/terraform/simulation"
    terraform apply -auto-approve 2>&1 | tail -5
    echo "    ✅ Terraform apply complete"
}

# ---------------------------------------------------------------------------
# Step 2: Build and deploy the load generator
# ---------------------------------------------------------------------------
step_build_deploy() {
    echo ">>> Step 2: Building and deploying load generator..."

    local IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/loadgen/loadgen:latest"

    # Build with Cloud Build
    echo "    Building container image..."
    cd "$PROJECT_ROOT/loadgen"
    gcloud builds submit \
        --project="$PROJECT_ID" \
        --tag="$IMAGE" \
        --quiet 2>&1 | tail -5

    echo "    Deploying to Cloud Run..."
    # Get Cloud SQL private IP
    local DB_HOST
    DB_HOST=$(gcloud sql instances describe "$CLOUDSQL_INSTANCE" \
        --project="$PROJECT_ID" \
        --format="value(ipAddresses[0].ipAddress)" 2>/dev/null | head -1)

    # If private IP not found, try from terraform
    if [ -z "$DB_HOST" ]; then
        DB_HOST=$(cd "$PROJECT_ROOT/terraform/simulation" && \
            terraform output -raw cloudsql_private_ip 2>/dev/null)
    fi

    echo "    Cloud SQL private IP: $DB_HOST"

    gcloud run deploy loadgen \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --image="$IMAGE" \
        --set-env-vars="DB_HOST=${DB_HOST},DB_PORT=5432,DB_USER=${DB_USER},DB_PASS=${DB_PASS},DB_NAME=${DB_NAME},INTERVAL_SECONDS=5" \
        --vpc-connector="monitoring-lab-connector" \
        --vpc-egress=private-ranges-only \
        --min-instances=1 \
        --max-instances=1 \
        --memory=256Mi \
        --cpu=1 \
        --no-allow-unauthenticated \
        --quiet 2>&1 | tail -5

    echo "    ✅ Load generator deployed and running"
}

# ---------------------------------------------------------------------------
# Step 3: Create PostgreSQL replication slot for Datastream
# ---------------------------------------------------------------------------
step_replication_slot() {
    echo ">>> Step 3: Setting up PostgreSQL replication..."

    local PUBLIC_IP
    PUBLIC_IP=$(gcloud sql instances describe "$CLOUDSQL_INSTANCE" \
        --project="$PROJECT_ID" \
        --format="value(ipAddresses.filter(type=PRIMARY).ipAddress)" 2>/dev/null)

    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP=$(gcloud sql instances describe "$CLOUDSQL_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(ipAddresses[1].ipAddress)" 2>/dev/null)
    fi

    echo "    Cloud SQL public IP: $PUBLIC_IP"

    # Create replication slot and publication
    PGPASSWORD="$DB_PASS" psql -h "$PUBLIC_IP" -U "$DB_USER" -d "$DB_NAME" -c "
        -- Create replication slot if not exists
        SELECT CASE
            WHEN NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'datastream_slot')
            THEN (SELECT pg_create_logical_replication_slot('datastream_slot', 'pgoutput'))::text
            ELSE 'slot already exists'
        END AS result;
    " 2>&1 || echo "    ⚠️  Replication slot creation skipped (may already exist)"

    PGPASSWORD="$DB_PASS" psql -h "$PUBLIC_IP" -U "$DB_USER" -d "$DB_NAME" -c "
        -- Create publication for all tables
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'datastream_pub') THEN
                CREATE PUBLICATION datastream_pub FOR ALL TABLES;
            END IF;
        END \$\$;
    " 2>&1 || echo "    ⚠️  Publication creation skipped (may already exist)"

    echo "    ✅ Replication slot and publication configured"
}

# ---------------------------------------------------------------------------
# Step 4: Start the Datastream stream
# ---------------------------------------------------------------------------
step_start_datastream() {
    echo ">>> Step 4: Starting Datastream stream..."

    local STREAM_STATE
    STREAM_STATE=$(gcloud datastream streams describe "$DATASTREAM_STREAM" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --format="value(state)" 2>/dev/null)

    echo "    Current stream state: $STREAM_STATE"

    if [ "$STREAM_STATE" = "NOT_STARTED" ] || [ "$STREAM_STATE" = "PAUSED" ]; then
        gcloud datastream streams update "$DATASTREAM_STREAM" \
            --project="$PROJECT_ID" \
            --location="$REGION" \
            --state=RUNNING \
            --update-mask=state \
            --quiet 2>&1
        echo "    ✅ Datastream stream started"
    elif [ "$STREAM_STATE" = "RUNNING" ]; then
        echo "    ✅ Stream already running"
    else
        echo "    ⚠️  Stream is in state: $STREAM_STATE — manual intervention may be needed"
    fi
}

# ---------------------------------------------------------------------------
# Step 5: Deploy DAGs to Composer
# ---------------------------------------------------------------------------
step_deploy_dags() {
    echo ">>> Step 5: Deploying DAGs to Composer..."

    local DAG_BUCKET
    DAG_BUCKET=$(gcloud composer environments describe "$COMPOSER_ENV" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --format="value(config.dagGcsPrefix)" 2>/dev/null)

    echo "    DAG bucket: $DAG_BUCKET"

    # Upload each DAG file
    for dag_file in "$PROJECT_ROOT"/dags/*.py; do
        local basename
        basename=$(basename "$dag_file")
        echo "    Uploading $basename..."
        gsutil cp "$dag_file" "$DAG_BUCKET/$basename" 2>&1
    done

    echo "    ✅ DAGs deployed to Composer"
}

# ---------------------------------------------------------------------------
# Step 6: Unpause DAGs
# ---------------------------------------------------------------------------
step_unpause_dags() {
    echo ">>> Step 6: Unpausing DAGs..."

    for dag_id in raw_to_silver silver_to_datamart chaos_monkey; do
        echo "    Unpausing $dag_id..."
        gcloud composer environments run "$COMPOSER_ENV" \
            --project="$PROJECT_ID" \
            --location="$REGION" \
            dags unpause -- "$dag_id" 2>&1 | tail -2 || true
    done

    echo "    ✅ DAGs unpaused"
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
main() {
    local start_time
    start_time=$(date +%s)

    step_terraform
    echo ""
    step_build_deploy
    echo ""
    step_replication_slot
    echo ""
    step_start_datastream
    echo ""
    step_deploy_dags
    echo ""
    step_unpause_dags

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    echo ""
    echo "============================================"
    echo "  ✅ Pipeline setup complete!"
    echo "  Total time: ${elapsed}s"
    echo "============================================"
    echo ""
    echo "Verify:"
    echo "  Load generator: gcloud run services describe loadgen --project=$PROJECT_ID --region=$REGION --format='value(status.url)'"
    echo "  Datastream:     gcloud datastream streams describe $DATASTREAM_STREAM --project=$PROJECT_ID --location=$REGION --format='value(state)'"
    echo "  Composer:       gcloud composer environments describe $COMPOSER_ENV --project=$PROJECT_ID --location=$REGION --format='value(state)'"
}

# Allow running individual steps
if [ "${1:-}" = "--step" ]; then
    shift
    "step_$1"
else
    main
fi
