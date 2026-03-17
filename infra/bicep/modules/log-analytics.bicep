// ---------------------------------------------------------------------------
// Module: Log Analytics Workspace + Sentinel
// ---------------------------------------------------------------------------
@description('Resource name prefix')
param prefix string

@description('Primary location')
param location string

@description('Log retention in days')
param retentionDays int = 90

@description('Tags')
param tags object = {}

// --- Log Analytics Workspace ---
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
  }
}

// --- Enable Microsoft Sentinel via the SecurityInsights solution ---
resource sentinelSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${workspace.name})'
  location: location
  properties: {
    workspaceResourceId: workspace.id
  }
  plan: {
    name: 'SecurityInsights(${workspace.name})'
    publisher: 'Microsoft'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
  }
}

// --- Sentinel Analytics Rule: WAF Block Alert ---
// NOTE: Sentinel alert rules via ARM can fail if the workspace hasn't fully
// onboarded. Create alert rules via the portal or CLI after deployment.
// See docs/soc-automation-stub.md for the rule definition.

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output workspaceCustomerId string = workspace.properties.customerId
