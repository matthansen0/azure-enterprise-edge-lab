// ---------------------------------------------------------------------------
// Main Bicep — CDN + WAF Sandbox Environment
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Resource naming prefix (lowercase, no hyphens for storage)')
param prefix string = 'afdemo'

@description('Primary region')
param locationA string = 'eastus2'

@description('Secondary region (failover)')
param locationB string = 'westus2'

@description('WAF mode')
@allowed(['Detection', 'Prevention'])
param wafMode string = 'Prevention'

@description('Rate limit threshold (requests per minute)')
param rateLimitThreshold int = 100

@description('Log retention days')
param logRetentionDays int = 90

@description('Deploy Security Copilot pay-as-you-go capacity (~$4/hr per SCU)')
param deploySecurityCopilot bool = true

@description('Tags applied to all resources')
param tags object = {
  environment: 'demo'
  project: 'afd-sandbox'
  purpose: 'cdn-waf-sandbox'
}

// ---------------------------------------------------------------------------
// Log Analytics + Sentinel
// ---------------------------------------------------------------------------
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    prefix: prefix
    location: locationA
    retentionDays: logRetentionDays
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// WAF Policy
// ---------------------------------------------------------------------------
module wafPolicy 'modules/waf-policy.bicep' = {
  name: 'waf-policy'
  params: {
    prefix: prefix
    mode: wafMode
    rateLimitThreshold: rateLimitThreshold
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Container Registry (shared — for azd image builds)
// ---------------------------------------------------------------------------
module containerRegistry 'modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    prefix: prefix
    location: locationA
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Origin A (primary)
// ---------------------------------------------------------------------------
module originA 'modules/origin-webapp.bicep' = {
  name: 'origin-a'
  params: {
    prefix: prefix
    location: locationA
    originLabel: 'a'
    serviceName: 'origin-a'
    acrLoginServer: containerRegistry.outputs.acrLoginServer
    acrName: containerRegistry.outputs.acrName
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Origin B (secondary — failover)
// ---------------------------------------------------------------------------
module originB 'modules/origin-webapp.bicep' = {
  name: 'origin-b'
  params: {
    prefix: prefix
    location: locationB
    originLabel: 'b'
    serviceName: 'origin-b'
    acrLoginServer: containerRegistry.outputs.acrLoginServer
    acrName: containerRegistry.outputs.acrName
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Azure Front Door Premium
// ---------------------------------------------------------------------------
module frontDoor 'modules/frontdoor.bicep' = {
  name: 'frontdoor'
  params: {
    prefix: prefix
    originAHostname: originA.outputs.hostname
    originBHostname: originB.outputs.hostname
    wafPolicyId: wafPolicy.outputs.wafPolicyId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Diagnostic Settings (Front Door + Container Apps → Log Analytics)
// ---------------------------------------------------------------------------
module diagnostics 'modules/diagnostics.bicep' = {
  name: 'diagnostics'
  params: {
    prefix: prefix
    frontDoorProfileName: frontDoor.outputs.profileName
    workspaceId: logAnalytics.outputs.workspaceId
    caeNameA: originA.outputs.environmentName
    caeNameB: originB.outputs.environmentName
  }
}

// ---------------------------------------------------------------------------
// Sentinel Content Hub Solutions + Azure Monitor Solutions
// ---------------------------------------------------------------------------
module sentinelContent 'modules/sentinel-content.bicep' = {
  name: 'sentinel-content'
  params: {
    workspaceId: logAnalytics.outputs.workspaceId
    workspaceName: logAnalytics.outputs.workspaceName
    location: locationA
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Azure Monitor Workbooks (Traffic Analytics + WAF Security)
// ---------------------------------------------------------------------------
module monitorWorkbooks 'modules/monitor-workbooks.bicep' = {
  name: 'monitor-workbooks'
  params: {
    prefix: prefix
    location: locationA
    workspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Microsoft Security Copilot — Pay-as-you-go SCU Capacity
// ---------------------------------------------------------------------------
module securityCopilot 'modules/security-copilot.bicep' = if (deploySecurityCopilot) {
  name: 'security-copilot'
  params: {
    prefix: prefix
    location: 'eastus' // Security Copilot only available in: australiaeast, eastus, uksouth, westeurope
    numberOfUnits: 1
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Dashboard (Workbook — original CDN/WAF overview)
// ---------------------------------------------------------------------------
module dashboard 'modules/dashboard.bicep' = {
  name: 'dashboard'
  params: {
    prefix: prefix
    location: locationA
    workspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output frontDoorEndpoint string = frontDoor.outputs.endpointHostName
output frontDoorProfileName string = frontDoor.outputs.profileName
output originAHostname string = originA.outputs.hostname
output originBHostname string = originB.outputs.hostname
output originAAppName string = originA.outputs.appName
output originBAppName string = originB.outputs.appName
output originAEnvName string = originA.outputs.environmentName
output originBEnvName string = originB.outputs.environmentName
output logAnalyticsWorkspace string = logAnalytics.outputs.workspaceName
output wafPolicyName string = wafPolicy.outputs.wafPolicyName
output customDomainConfig array = frontDoor.outputs.customDomainConfig
#disable-next-line outputs-should-not-contain-secrets
output securityCopilotCapacity string = deploySecurityCopilot && securityCopilot != null ? securityCopilot!.outputs.capacityName : 'not-deployed'

// azd-required outputs
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.acrLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.acrName
