#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Post-deploy hook: wait for Front Door endpoint to become reachable
# New Front Door Premium deployments take 5-15 minutes for global propagation.
# This script polls the health endpoint until it returns HTTP 200.
# ---------------------------------------------------------------------------
set -euo pipefail

MAX_WAIT=1500  # 25 minutes — first deploy can exceed 15 min
INTERVAL=20    # seconds between checks

RG="${AZURE_RESOURCE_GROUP:-${DEMO_RG:-rg-afd-demo}}"
PREFIX="${DEMO_PREFIX:-afdemo}"
PROFILE="${PREFIX}-afd"
ENDPOINT_NAME="${PREFIX}-endpoint"

# ---------------------------------------------------------------------------
# If Security Copilot capacity was requested, verify it actually exists —
# a silent skip (e.g. RP not registered, quota, region) should be visible.
# ---------------------------------------------------------------------------
if [ "$(echo "${DEPLOY_SECURITY_COPILOT:-false}" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  CAPACITY_NAME="${PREFIX}-seccopilot"
  echo "DEPLOY_SECURITY_COPILOT=true — verifying '$CAPACITY_NAME' capacity was actually created..."
  if az resource show --resource-group "$RG" --resource-type Microsoft.SecurityCopilot/capacities --name "$CAPACITY_NAME" -o none 2>/dev/null; then
    echo "✅ Security Copilot capacity '$CAPACITY_NAME' exists."
  else
    echo "❌ Security Copilot capacity '$CAPACITY_NAME' was NOT found, even though DEPLOY_SECURITY_COPILOT=true."
    echo "   Check: az provider show --namespace Microsoft.SecurityCopilot --query registrationState"
    echo "   and confirm your subscription has Security Copilot preview access/quota in eastus."
  fi
  echo ""
fi

# Get the Front Door hostname
HOSTNAME=$(az afd endpoint show \
  --resource-group "$RG" \
  --profile-name "$PROFILE" \
  --endpoint-name "$ENDPOINT_NAME" \
  --query "hostName" -o tsv 2>/dev/null)

if [ -z "$HOSTNAME" ]; then
  echo "⚠  Could not retrieve Front Door endpoint hostname. Skipping readiness check."
  exit 0
fi

URL="https://${HOSTNAME}/api/health"

echo ""
echo "=============================================="
echo "  Front Door Readiness Check"
echo "=============================================="
echo "  Endpoint : ${HOSTNAME}"
echo "  Polling  : ${URL}"
echo "  Timeout  : $((MAX_WAIT / 60)) minutes"
echo "=============================================="
echo ""
echo "Front Door propagation typically takes 5-15 minutes, but first deploys can take up to 25 minutes."
echo ""

SECONDS=0
while [ $SECONDS -lt $MAX_WAIT ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$URL" 2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "200" ]; then
    ELAPSED=$((SECONDS / 60))
    echo "✅ Front Door is live! (HTTP 200 after ~${ELAPSED}m)"
    echo ""
    echo "  Homepage : https://${HOSTNAME}/"
    echo "  Health   : https://${HOSTNAME}/api/health"
    echo ""
    break
  fi

  ELAPSED_MIN=$((SECONDS / 60))
  ELAPSED_SEC=$((SECONDS % 60))
  echo "  ⏳ HTTP ${HTTP_CODE} — waiting... (${ELAPSED_MIN}m ${ELAPSED_SEC}s elapsed)"
  sleep "$INTERVAL"
done

if [ "$HTTP_CODE" != "200" ]; then
  echo ""
  echo "⚠  Endpoint did not return HTTP 200 within $((MAX_WAIT / 60)) minutes."
  echo "   The endpoint may still be propagating. Keep checking manually:"
  echo ""
  echo "   curl -sI https://${HOSTNAME}/api/health"
  echo "   curl -s  https://${HOSTNAME}/"
  echo ""
fi

exit 0  # Don't fail the deployment — propagation may just need more time
