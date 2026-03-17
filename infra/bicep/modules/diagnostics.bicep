// ---------------------------------------------------------------------------
// Module: Diagnostic Settings — Full Logging → Log Analytics
// Covers Front Door Premium and both Container Apps Environments
// ---------------------------------------------------------------------------
@description('Front Door profile name')
param frontDoorProfileName string

@description('Log Analytics workspace ID')
param workspaceId string

@description('Resource name prefix')
param prefix string

@description('Container Apps Environment name for origin A')
param caeNameA string = ''

@description('Container Apps Environment name for origin B')
param caeNameB string = ''

// -------------------------------------------------------
// Front Door → Log Analytics (all logs + all metrics)
// -------------------------------------------------------
resource existingFrontDoor 'Microsoft.Cdn/profiles@2024-02-01' existing = {
  name: frontDoorProfileName
}

resource afdDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${prefix}-afd-diag'
  scope: existingFrontDoor
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: true
      }
      {
        category: 'FrontDoorHealthProbeLog'
        enabled: true
      }
      {
        category: 'FrontDoorWebApplicationFirewallLog'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// -------------------------------------------------------
// Container Apps Environment A → Log Analytics
// -------------------------------------------------------
resource caeA 'Microsoft.App/managedEnvironments@2024-03-01' existing = if (!empty(caeNameA)) {
  name: caeNameA
}

resource caeDiagA 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(caeNameA)) {
  name: '${prefix}-cae-a-diag'
  scope: caeA
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'ContainerAppConsoleLogs'
        enabled: true
      }
      {
        category: 'ContainerAppSystemLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// -------------------------------------------------------
// Container Apps Environment B → Log Analytics
// -------------------------------------------------------
resource caeB 'Microsoft.App/managedEnvironments@2024-03-01' existing = if (!empty(caeNameB)) {
  name: caeNameB
}

resource caeDiagB 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(caeNameB)) {
  name: '${prefix}-cae-b-diag'
  scope: caeB
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'ContainerAppConsoleLogs'
        enabled: true
      }
      {
        category: 'ContainerAppSystemLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
