#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# toggle-failover.sh — Enable/disable an origin to exercise failover
# Usage: bash scripts/toggle-failover.sh disable origin-b
#        bash scripts/toggle-failover.sh enable  origin-b
#
# Override defaults: DEMO_PREFIX=afdemo DEMO_RG=rg-afd-demo bash scripts/toggle-failover.sh ...
# ---------------------------------------------------------------------------
set -euo pipefail

PREFIX="${DEMO_PREFIX:-afdemo}"
RG="${DEMO_RG:-rg-afd-demo}"
PROFILE_NAME="${PREFIX}-afd"
ORIGIN_GROUP="default-origin-group"

ACTION="${1:-disable}"    # enable | disable
ORIGIN="${2:-origin-b}"   # origin-a | origin-b

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
