#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Pre-provision hook: wait for in-progress resource group deletion
# Front Door Premium profiles take 15-25 minutes to delete, and azd up
# will fail if the RG is still being deleted from a previous azd down.
# ---------------------------------------------------------------------------
set -euo pipefail

RG="${AZURE_RESOURCE_GROUP:-${DEMO_RG:-rg-afd-demo}}"

echo "Checking if resource group '$RG' is in a Deleting state..."

if STATE=$(az group show --name "$RG" --query "properties.provisioningState" -o tsv 2>/dev/null); then
  if [ "$STATE" = "Deleting" ]; then
    echo "Resource group is still deleting (Front Door cleanup takes 15-25 min)."
    echo "Waiting for deletion to complete..."
    SECONDS=0
    while az group show --name "$RG" --query "properties.provisioningState" -o tsv 2>/dev/null | grep -q "Deleting"; do
      elapsed=$((SECONDS / 60))
      echo "  Still deleting... (${elapsed}m elapsed)"
      sleep 30
    done
    echo "Resource group deleted. Proceeding with provisioning."
  else
    echo "Resource group exists (state: $STATE). Proceeding."
  fi
else
  echo "Resource group does not exist. Proceeding."
fi
