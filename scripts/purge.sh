#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# purge.sh — Purge a Front Door cache path and verify
# Usage:
#   AFD_FQDN=<endpoint>.azurefd.net bash scripts/purge.sh /static/version.json
#   bash scripts/purge.sh /static/version.json   # auto-discovers via az CLI
# ---------------------------------------------------------------------------
set -euo pipefail

PREFIX="${DEMO_PREFIX:-afdemo}"
RG="${DEMO_RG:-rg-afd-demo}"
PURGE_PATH="${1:-/static/version.json}"

PROFILE_NAME="${PREFIX}-afd"
ENDPOINT_NAME="${PREFIX}-endpoint"

echo "============================================"
echo "  Cache Purge Demo"
echo "============================================"

# Resolve Front Door FQDN — env var first, then az CLI
if [[ -n "${AFD_FQDN:-}" ]]; then
  AFD_ENDPOINT="$AFD_FQDN"
elif AFD_ENDPOINT=$(az afd endpoint show \
  --resource-group "$RG" \
  --profile-name "$PROFILE_NAME" \
  --endpoint-name "$ENDPOINT_NAME" \
  --query hostName -o tsv 2>/dev/null); then
  : # success
else
  echo "ERROR: Could not resolve Front Door endpoint."
  echo "Set AFD_FQDN env var:  AFD_FQDN=<endpoint>.azurefd.net bash $0"
  exit 1
fi

BASE_URL="https://$AFD_ENDPOINT"

# 1. Fetch before purge
echo "[1/3] Fetching before purge..."
echo "  URL: $BASE_URL$PURGE_PATH"
BEFORE=$(curl -sI "$BASE_URL$PURGE_PATH" 2>/dev/null | grep -i "x-cache\|age\|date" || echo "(no cache headers)")
echo "  $BEFORE"

# 2. Purge
echo "[2/3] Purging path: $PURGE_PATH ..."
az afd endpoint purge \
  --resource-group "$RG" \
  --profile-name "$PROFILE_NAME" \
  --endpoint-name "$ENDPOINT_NAME" \
  --content-paths "$PURGE_PATH" \
  --output none

echo "  Purge request submitted. Waiting 10s for propagation..."
sleep 10

# 3. Fetch after purge
echo "[3/3] Fetching after purge..."
AFTER=$(curl -sI "$BASE_URL$PURGE_PATH" 2>/dev/null | grep -i "x-cache\|age\|date" || echo "(no cache headers)")
echo "  $AFTER"

echo ""
echo "  ✅ Purge complete. Compare 'age' header: should be reset to 0 or missing (cache miss)."
echo "============================================"
