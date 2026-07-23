#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup_notification_channels.sh
#
# Creates notification channels in Cloud Monitoring for receiving alerts.
# Run this FIRST before setting up alerting policies.
#
# Prerequisites:
#   - gcloud CLI authenticated with sufficient permissions
#   - Cloud Monitoring API enabled
#
# Usage:
#   export GCP_PROJECT_ID="your-project-id"
#   export ALERT_EMAIL="oncall@yourcompany.com"
#   bash monitoring/setup_notification_channels.sh
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
GCP_PROJECT_ID="${GCP_PROJECT_ID:?ERROR: Set GCP_PROJECT_ID environment variable}"
ALERT_EMAIL="${ALERT_EMAIL:?ERROR: Set ALERT_EMAIL environment variable}"
PUBSUB_TOPIC="composer-alerts"

echo "============================================="
echo " Setting up Notification Channels"
echo " Project: ${GCP_PROJECT_ID}"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# 1. Enable required APIs
# ---------------------------------------------------------------------------
echo "[1/4] Enabling required APIs..."
gcloud services enable monitoring.googleapis.com \
    --project="${GCP_PROJECT_ID}" --quiet
gcloud services enable pubsub.googleapis.com \
    --project="${GCP_PROJECT_ID}" --quiet
echo "       ✓ Cloud Monitoring API enabled"
echo "       ✓ Cloud Pub/Sub API enabled"
echo ""

# ---------------------------------------------------------------------------
# 2. Create email notification channel
# ---------------------------------------------------------------------------
echo "[2/4] Creating email notification channel..."

# Check if it already exists
EXISTING_EMAIL=$(gcloud monitoring channels list \
    --project="${GCP_PROJECT_ID}" \
    --filter="type='email' AND labels.email_address='${ALERT_EMAIL}'" \
    --format="value(name)" 2>/dev/null || true)

if [ -n "${EXISTING_EMAIL}" ]; then
    echo "       ⚠ Email channel already exists: ${EXISTING_EMAIL}"
    EMAIL_CHANNEL_ID="${EXISTING_EMAIL}"
else
    EMAIL_CHANNEL_ID=$(gcloud monitoring channels create \
        --project="${GCP_PROJECT_ID}" \
        --display-name="Composer Alerts - Email" \
        --type=email \
        --channel-labels="email_address=${ALERT_EMAIL}" \
        --description="Email notifications for Cloud Composer pipeline alerts" \
        --format="value(name)")
    echo "       ✓ Created email channel: ${EMAIL_CHANNEL_ID}"
fi
echo ""

# ---------------------------------------------------------------------------
# 3. Create Pub/Sub topic and subscription
# ---------------------------------------------------------------------------
echo "[3/4] Creating Pub/Sub topic for programmatic alerts..."

# Create topic
if gcloud pubsub topics describe "${PUBSUB_TOPIC}" \
    --project="${GCP_PROJECT_ID}" &>/dev/null; then
    echo "       ⚠ Topic '${PUBSUB_TOPIC}' already exists"
else
    gcloud pubsub topics create "${PUBSUB_TOPIC}" \
        --project="${GCP_PROJECT_ID}" \
        --labels="purpose=composer-monitoring"
    echo "       ✓ Created topic: ${PUBSUB_TOPIC}"
fi

# Create subscription (for manual pull / debugging)
SUB_NAME="${PUBSUB_TOPIC}-debug-sub"
if gcloud pubsub subscriptions describe "${SUB_NAME}" \
    --project="${GCP_PROJECT_ID}" &>/dev/null; then
    echo "       ⚠ Subscription '${SUB_NAME}' already exists"
else
    gcloud pubsub subscriptions create "${SUB_NAME}" \
        --project="${GCP_PROJECT_ID}" \
        --topic="${PUBSUB_TOPIC}" \
        --ack-deadline=60 \
        --message-retention-duration=1d
    echo "       ✓ Created subscription: ${SUB_NAME}"
fi
echo ""

# ---------------------------------------------------------------------------
# 4. Create Pub/Sub notification channel in Cloud Monitoring
# ---------------------------------------------------------------------------
echo "[4/4] Creating Pub/Sub notification channel..."

# Note: Pub/Sub notification channels require a JSON descriptor
PUBSUB_CHANNEL_FILE=$(mktemp)
cat > "${PUBSUB_CHANNEL_FILE}" <<EOF
{
  "type": "pubsub",
  "displayName": "Composer Alerts - Pub/Sub",
  "description": "Pub/Sub notifications for Cloud Composer pipeline alerts",
  "labels": {
    "topic": "projects/${GCP_PROJECT_ID}/topics/${PUBSUB_TOPIC}"
  }
}
EOF

EXISTING_PUBSUB=$(gcloud monitoring channels list \
    --project="${GCP_PROJECT_ID}" \
    --filter="type='pubsub' AND displayName='Composer Alerts - Pub/Sub'" \
    --format="value(name)" 2>/dev/null || true)

if [ -n "${EXISTING_PUBSUB}" ]; then
    echo "       ⚠ Pub/Sub channel already exists: ${EXISTING_PUBSUB}"
    PUBSUB_CHANNEL_ID="${EXISTING_PUBSUB}"
else
    PUBSUB_CHANNEL_ID=$(gcloud monitoring channels create \
        --project="${GCP_PROJECT_ID}" \
        --channel-content-from-file="${PUBSUB_CHANNEL_FILE}" \
        --format="value(name)")
    echo "       ✓ Created Pub/Sub channel: ${PUBSUB_CHANNEL_ID}"
fi
rm -f "${PUBSUB_CHANNEL_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "============================================="
echo " Notification Channels Setup Complete!"
echo "============================================="
echo ""
echo " Email Channel:  ${EMAIL_CHANNEL_ID:-'see above'}"
echo " Pub/Sub Channel: ${PUBSUB_CHANNEL_ID:-'see above'}"
echo " Pub/Sub Topic:  projects/${GCP_PROJECT_ID}/topics/${PUBSUB_TOPIC}"
echo ""
echo " NEXT STEP: Run setup_alerting_policies.sh"
echo ""
echo " To list all channels:"
echo "   gcloud monitoring channels list --project=${GCP_PROJECT_ID}"
echo "============================================="
