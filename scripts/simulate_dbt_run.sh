#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# simulate_dbt_run.sh
#
# Simulates a dbt transformation job.
# Reads the FORCE_FAIL environment variable to control success/failure.
#
# Usage:
#   FORCE_FAIL=false bash simulate_dbt_run.sh   # succeeds
#   FORCE_FAIL=true  bash simulate_dbt_run.sh   # fails
# ---------------------------------------------------------------------------

set -euo pipefail

FORCE_FAIL="${FORCE_FAIL:-false}"

echo "============================================="
echo " dbt Run Simulation"
echo " Started at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================="
echo ""

# Simulate dependency resolution
echo "Running with dbt=1.7.0"
echo "Found 4 models, 3 tests, 1 snapshot, 0 seeds"
echo ""

# Simulate model compilation
echo "Concurrency: 4 threads (target='prod')"
echo ""

echo "1 of 4 START sql table model analytics.stg_users ..................... [RUN]"
sleep 1
echo "1 of 4 OK created sql table model analytics.stg_users ............... [CREATE TABLE 15234 rows in 2.1s]"
echo ""

echo "2 of 4 START sql table model analytics.stg_orders ................... [RUN]"
sleep 2
echo "2 of 4 OK created sql table model analytics.stg_orders .............. [CREATE TABLE 42891 rows in 3.4s]"
echo ""

echo "3 of 4 START sql table model analytics.fct_revenue .................. [RUN]"
sleep 2

if [ "${FORCE_FAIL}" = "true" ]; then
    echo "3 of 4 ERROR creating sql table model analytics.fct_revenue ........ [ERROR in 1.8s]"
    echo ""
    echo "Compilation Error in model fct_revenue (models/marts/fct_revenue.sql)"
    echo "  Database error: Column 'order_amount' not found in table 'stg_orders'"
    echo "  compiled SQL at target/compiled/analytics/models/marts/fct_revenue.sql"
    echo ""
    echo "============================================="
    echo " Completed with 1 error and 0 warnings:"
    echo ""
    echo " FAIL 1  analytics.fct_revenue"
    echo ""
    echo " Done. FAIL=1 WARN=0 ERROR=1 SKIP=1 TOTAL=4"
    echo " Finished at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "============================================="
    exit 1
fi

echo "3 of 4 OK created sql table model analytics.fct_revenue ............. [CREATE TABLE 42891 rows in 4.2s]"
echo ""

echo "4 of 4 START sql table model analytics.dim_customers ................ [RUN]"
sleep 1
echo "4 of 4 OK created sql table model analytics.dim_customers ........... [CREATE TABLE 15234 rows in 1.9s]"
echo ""

echo "============================================="
echo " Completed successfully"
echo ""
echo " Done. PASS=4 WARN=0 ERROR=0 SKIP=0 TOTAL=4"
echo " Finished at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================="
exit 0
