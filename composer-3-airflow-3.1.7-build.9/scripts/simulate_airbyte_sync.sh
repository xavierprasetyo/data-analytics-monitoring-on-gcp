#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# simulate_airbyte_sync.sh
#
# Simulates an Airbyte data extraction job.
# Reads the FORCE_FAIL environment variable to control success/failure.
#
# Usage:
#   FORCE_FAIL=false bash simulate_airbyte_sync.sh   # succeeds
#   FORCE_FAIL=true  bash simulate_airbyte_sync.sh   # fails
# ---------------------------------------------------------------------------

set -euo pipefail

FORCE_FAIL="${FORCE_FAIL:-false}"

echo "============================================="
echo " Airbyte Sync Simulation"
echo " Started at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================="
echo ""

# Simulate connection setup
echo "[1/4] Connecting to source database..."
sleep 2
echo "       ✓ Connected to source: postgres://source-db:5432/app_data"
echo ""

# Simulate schema discovery
echo "[2/4] Discovering schema..."
sleep 1
echo "       ✓ Found 3 streams: users, orders, products"
echo "       ✓ Sync mode: incremental (cursor: updated_at)"
echo ""

# Simulate data extraction
echo "[3/4] Extracting data..."
sleep 3

if [ "${FORCE_FAIL}" = "true" ]; then
    echo "       ✗ ERROR: Connection to source database timed out after 30s"
    echo "       ✗ ERROR: Airbyte sync failed with status FAILED"
    echo ""
    echo "============================================="
    echo " Sync Status: FAILED"
    echo " Finished at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "============================================="
    exit 1
fi

echo "       ✓ Extracted 15,234 records from 'users'"
echo "       ✓ Extracted 42,891 records from 'orders'"
echo "       ✓ Extracted 1,205 records from 'products'"
echo ""

# Simulate loading to destination
echo "[4/4] Loading to BigQuery destination..."
sleep 2
echo "       ✓ Loaded all records to dataset 'raw_data'"
echo ""

echo "============================================="
echo " Sync Status: SUCCEEDED"
echo " Records synced: 59,330"
echo " Duration: ~8 seconds"
echo " Finished at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================="
exit 0
