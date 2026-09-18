# ---------------------------------------------------------------------------
# Post-deploy hook: wait for Front Door endpoint to become reachable
# New Front Door Premium deployments take 5-15 minutes for global propagation.
# This script polls the health endpoint until it returns HTTP 200.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

$MaxWait  = 1500  # 25 minutes - first deploy can exceed 15 min
$Interval = 20    # seconds between checks

$RG          = if ($env:AZURE_RESOURCE_GROUP) { $env:AZURE_RESOURCE_GROUP } elseif ($env:DEMO_RG) { $env:DEMO_RG } else { 'rg-afd-demo' }
$Prefix      = if ($env:DEMO_PREFIX) { $env:DEMO_PREFIX } else { 'afdemo' }
$Profile     = "$Prefix-afd"
$EndpointName = "$Prefix-endpoint"

# ---------------------------------------------------------------------------
# If Security Copilot capacity was requested, verify it actually exists —
# a silent skip (e.g. RP not registered, quota, region) should be visible.
# ---------------------------------------------------------------------------
if ($env:DEPLOY_SECURITY_COPILOT -and $env:DEPLOY_SECURITY_COPILOT.ToLower() -eq 'true') {
    $CapacityName = "$Prefix-seccopilot"
    Write-Host "DEPLOY_SECURITY_COPILOT=true - verifying '$CapacityName' capacity was actually created..."
    az resource show --resource-group $RG --resource-type Microsoft.SecurityCopilot/capacities --name $CapacityName -o none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Security Copilot capacity '$CapacityName' exists."
    } else {
        Write-Host "Security Copilot capacity '$CapacityName' was NOT found, even though DEPLOY_SECURITY_COPILOT=true."
        Write-Host "  Check: az provider show --namespace Microsoft.SecurityCopilot --query registrationState"
        Write-Host "  and confirm your subscription has Security Copilot preview access/quota in eastus."
    }
    Write-Host ""
}

# Get the Front Door hostname
$Hostname = az afd endpoint show `
  --resource-group $RG `
  --profile-name $Profile `
  --endpoint-name $EndpointName `
  --query "hostName" -o tsv 2>$null

if (-not $Hostname) {
    Write-Host "`nWarning: Could not retrieve Front Door endpoint hostname. Skipping readiness check."
    exit 0
}

$Url = "https://$Hostname/api/health"

Write-Host ""
Write-Host "=============================================="
Write-Host "  Front Door Readiness Check"
Write-Host "=============================================="
Write-Host "  Endpoint : $Hostname"
Write-Host "  Polling  : $Url"
Write-Host "  Timeout  : $([math]::Floor($MaxWait / 60)) minutes"
Write-Host "=============================================="
Write-Host ""
Write-Host "Front Door propagation typically takes 5-15 minutes, but first deploys can take up to 25 minutes."
Write-Host ""

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

while ($Stopwatch.Elapsed.TotalSeconds -lt $MaxWait) {
    try {
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        $StatusCode = $Response.StatusCode
    } catch {
        $StatusCode = 0
        if ($_.Exception.Response) {
            $StatusCode = [int]$_.Exception.Response.StatusCode
        }
    }

    if ($StatusCode -eq 200) {
        $Elapsed = [math]::Floor($Stopwatch.Elapsed.TotalMinutes)
        Write-Host "Front Door is live! (HTTP 200 after ~${Elapsed}m)"
        Write-Host ""
        Write-Host "  Homepage : https://$Hostname/"
        Write-Host "  Health   : https://$Hostname/api/health"
        Write-Host ""
        exit 0
    }

    $ElapsedMin = [math]::Floor($Stopwatch.Elapsed.TotalMinutes)
    $ElapsedSec = [math]::Floor($Stopwatch.Elapsed.TotalSeconds) % 60
    Write-Host "  HTTP $StatusCode - waiting... (${ElapsedMin}m ${ElapsedSec}s elapsed)"
    Start-Sleep -Seconds $Interval
}

$ElapsedMin = [math]::Floor($Stopwatch.Elapsed.TotalMinutes)
Write-Host ""
Write-Host "Timed out after ${ElapsedMin}m. The endpoint may still be propagating."
Write-Host "Keep checking manually:"
Write-Host ""
Write-Host "  curl -sI https://$Hostname/api/health"
Write-Host "  curl -s  https://$Hostname/"
Write-Host ""
exit 0
