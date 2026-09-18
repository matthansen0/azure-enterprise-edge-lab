# ---------------------------------------------------------------------------
# Pre-provision hook: wait for in-progress resource group deletion
# Front Door Premium profiles take 15-25 minutes to delete, and azd up
# will fail if the RG is still being deleted from a previous azd down.
# ---------------------------------------------------------------------------

$RG = if ($env:AZURE_RESOURCE_GROUP) { $env:AZURE_RESOURCE_GROUP } elseif ($env:DEMO_RG) { $env:DEMO_RG } else { 'rg-afd-demo' }

Write-Host "Checking if resource group '$RG' is in a Deleting state..."

$State = az group show --name $RG --query "properties.provisioningState" -o tsv 2>$null

if ($State) {
    if ($State -eq 'Deleting') {
        Write-Host "Resource group is still deleting (Front Door cleanup takes 15-25 min)."
        Write-Host "Waiting for deletion to complete..."
        $elapsedSeconds = 0
        while ((az group show --name $RG --query "properties.provisioningState" -o tsv 2>$null) -eq 'Deleting') {
            $elapsedMinutes = [math]::Floor($elapsedSeconds / 60)
            Write-Host "  Still deleting... (${elapsedMinutes}m elapsed)"
            Start-Sleep -Seconds 30
            $elapsedSeconds += 30
        }
        Write-Host "Resource group deleted. Proceeding with provisioning."
    } else {
        Write-Host "Resource group exists (state: $State). Proceeding."
    }
} else {
    Write-Host "Resource group does not exist. Proceeding."
}

# ---------------------------------------------------------------------------
# If Security Copilot capacity is requested, ensure the (preview) resource
# provider is registered first — an unregistered RP causes deployment to
# fail rather than silently skip, so surface this before provisioning starts.
# ---------------------------------------------------------------------------
if (($env:DEPLOY_SECURITY_COPILOT) -and ($env:DEPLOY_SECURITY_COPILOT.ToLower() -eq 'true')) {
    Write-Host "DEPLOY_SECURITY_COPILOT=true — checking Microsoft.SecurityCopilot provider registration..."
    $RpState = az provider show --namespace Microsoft.SecurityCopilot --query registrationState -o tsv 2>$null
    if (-not $RpState) { $RpState = 'NotFound' }
    if ($RpState -ne 'Registered') {
        Write-Host "Microsoft.SecurityCopilot is '$RpState' — registering now (this can take a few minutes)..."
        az provider register --namespace Microsoft.SecurityCopilot --wait
        Write-Host "Microsoft.SecurityCopilot registration complete."
    } else {
        Write-Host "Microsoft.SecurityCopilot is already registered."
    }
}
