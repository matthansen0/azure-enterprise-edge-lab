#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# generate-traffic.sh — Generate benign traffic to exercise rate limiting
# Uses 'hey' HTTP load generator or falls back to curl
#
# Usage:
#   AFD_FQDN=<your-endpoint>.azurefd.net bash scripts/generate-traffic.sh [requests] [concurrency]
#   bash scripts/generate-traffic.sh              # auto-discovers via az CLI
# ---------------------------------------------------------------------------
set -euo pipefail

RATE_LIMIT="${1:-150}"        # Total requests to send (default: 150, above 100/min threshold)
CONCURRENCY="${2:-10}"        # Concurrent workers

# Resolve the Front Door FQDN — accept env var, try azd, then fall back to az CLI
#
# Discovery order:
#   1. AFD_FQDN env var (explicit override)
#   2. azd env get-values (if azd binary is in PATH)
#   3. .azure/<default-env>/.env file (works even if azd isn't in PATH)
#   4. az CLI with DEMO_RG / DEMO_PREFIX defaults
# ---------------------------------------------------------------------------
_read_azd_value() {
  local key="$1"
  # Try azd binary first
  if command -v azd &>/dev/null; then
    azd env get-values 2>/dev/null | grep -oP "(?<=${key}=\").*(?=\")" && return
  fi
  # Fall back to reading the .env file from the default azd environment
  local azd_dir=".azure"
  if [[ -f "${azd_dir}/.env" ]]; then
    grep -oP "(?<=${key}=\").*(?=\")" "${azd_dir}/.env" && return
  fi
  # Check per-environment dirs (pick the default from config.json)
  if [[ -f "${azd_dir}/config.json" ]]; then
    local env_name
    env_name=$(grep -oP '(?<="defaultEnvironment":").*?(?=")' "${azd_dir}/config.json" 2>/dev/null || true)
    if [[ -n "$env_name" && -f "${azd_dir}/${env_name}/.env" ]]; then
      grep -oP "(?<=${key}=\").*(?=\")" "${azd_dir}/${env_name}/.env" && return
    fi
  fi
}

if [[ -n "${AFD_FQDN:-}" ]]; then
  AFD_ENDPOINT="$AFD_FQDN"
else
  AFD_ENDPOINT=$(_read_azd_value "frontDoorEndpoint" || true)
fi

if [[ -z "${AFD_ENDPOINT:-}" ]]; then
  PREFIX="${DEMO_PREFIX:-afdemo}"
  RG="${DEMO_RG:-$(_read_azd_value "AZURE_RESOURCE_GROUP" || echo "rg-afd-demo")}"
  PROFILE_NAME="${PREFIX}-afd"
  ENDPOINT_NAME="${PREFIX}-endpoint"
  if AFD_ENDPOINT=$(az afd endpoint show \
    --resource-group "$RG" \
    --profile-name "$PROFILE_NAME" \
    --endpoint-name "$ENDPOINT_NAME" \
    --query hostName -o tsv 2>/dev/null); then
    : # success
  else
    echo "ERROR: Could not resolve Front Door endpoint."
    echo "Set AFD_FQDN env var:  AFD_FQDN=<your-endpoint>.azurefd.net bash $0"
    exit 1
  fi
fi

BASE_URL="https://$AFD_ENDPOINT"

echo "============================================"
echo "  Traffic Generation — Rate Limit Exercise"
echo "============================================"
echo "  Target:      $BASE_URL/api/health"
echo "  Requests:    $RATE_LIMIT"
echo "  Concurrency: $CONCURRENCY"
echo "  Expected:    First ~100 succeed, remaining get 429/403 (rate limited)"
echo "============================================"

if command -v hey &>/dev/null; then
  echo "Using 'hey' load generator..."
  hey -n "$RATE_LIMIT" -c "$CONCURRENCY" -m GET "$BASE_URL/api/health"
else
  echo "Using curl (hey not found)..."
  for i in $(seq 1 "$RATE_LIMIT"); do
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/health" 2>/dev/null || echo "000")
    echo "  Request $i: HTTP $STATUS"
  done
fi

echo ""
echo "============================================"
echo "  Traffic generation complete."
echo "  Check WAF logs in the Azure Portal → Front Door → WAF logs"
echo "  or via Log Analytics KQL:"
echo "    AzureDiagnostics"
echo "    | where Category == 'FrontDoorWebApplicationFirewallLog'"
echo "    | where ruleName_s contains 'RateLimit'"
echo "    | summarize count() by action_s"
echo "============================================"
