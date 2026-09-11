#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# toggle-failover.sh — Enable/disable an origin to exercise failover
# Usage: bash scripts/toggle-failover.sh disable origin-a
#        bash scripts/toggle-failover.sh enable  origin-a
#
# origin-a is priority 1 (primary); disabling it forces Front Door onto origin-b.
#
# Override defaults: DEMO_PREFIX=afdemo DEMO_RG=rg-afd-demo bash scripts/toggle-failover.sh ...
# ---------------------------------------------------------------------------
set -euo pipefail

PREFIX="${DEMO_PREFIX:-afdemo}"

# Resource group: explicit env var, then the active azd environment, then the default.
RG="${DEMO_RG:-${AZURE_RESOURCE_GROUP:-}}"
if [[ -z "$RG" ]] && command -v azd >/dev/null 2>&1; then
  RG=$(azd env get-values 2>/dev/null | sed -n 's/^AZURE_RESOURCE_GROUP="\(.*\)"$/\1/p') || RG=""
fi
RG="${RG:-rg-afd-demo}"

PROFILE_NAME="${PREFIX}-afd"
ORIGIN_GROUP="default-origin-group"

ACTION="${1:-disable}"    # enable | disable
ORIGIN="${2:-origin-a}"   # origin-a | origin-b

if [ "$ACTION" = "disable" ]; then
  STATE="Disabled"
elif [ "$ACTION" = "enable" ]; then
  STATE="Enabled"
else
  echo "Usage: $0 <enable|disable> <origin-a|origin-b>"
  exit 1
fi

echo "============================================"
echo "  Origin Failover Exercise"
echo "============================================"
echo "  Action: $ACTION → $ORIGIN ($STATE)"
echo ""

az afd origin update \
  --resource-group "$RG" \
  --profile-name "$PROFILE_NAME" \
  --origin-group-name "$ORIGIN_GROUP" \
  --origin-name "$ORIGIN" \
  --enabled-state "$STATE" \
  --output none

echo "  ✅ Origin '$ORIGIN' is now $STATE."
echo ""

# Show current origin states
echo "  Current origin states:"
az afd origin list \
  --resource-group "$RG" \
  --profile-name "$PROFILE_NAME" \
  --origin-group-name "$ORIGIN_GROUP" \
  --query "[].{Name:name, State:enabledState}" \
  --output table

echo ""
echo "  Verify health: curl -s https://\$(az afd endpoint show --resource-group $RG --profile-name $PROFILE_NAME --endpoint-name ${PREFIX}-endpoint --query hostName -o tsv)/api/health | jq ."
echo "============================================"
