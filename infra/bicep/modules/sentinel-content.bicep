// ---------------------------------------------------------------------------
// Module: Microsoft Sentinel Content Hub Solutions & Azure Monitor Solutions
// Installs security content packs into Sentinel, plus Azure Monitor
// solutions for container and security monitoring.
// ---------------------------------------------------------------------------
@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Log Analytics workspace name')
param workspaceName string

@description('Location')
param location string

@description('Tags')
param tags object = {}

// ---------------------------------------------------------------------------
// Azure Monitor: Container Insights Solution
// Provides container-level metrics, logs, and workbooks
// ---------------------------------------------------------------------------
resource containerInsightsSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ContainerInsights(${workspaceName})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: workspaceId
  }
  plan: {
    name: 'ContainerInsights(${workspaceName})'
    publisher: 'Microsoft'
    product: 'OMSGallery/ContainerInsights'
    promotionCode: ''
  }
}

// ---------------------------------------------------------------------------
// Azure Monitor: Security & Audit Solution
// Provides security event baseline dashboards in Azure Monitor
// ---------------------------------------------------------------------------
resource securitySolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'Security(${workspaceName})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: workspaceId
  }
  plan: {
    name: 'Security(${workspaceName})'
    publisher: 'Microsoft'
    product: 'OMSGallery/Security'
    promotionCode: ''
  }
}

// ---------------------------------------------------------------------------
// Sentinel Content Hub: Azure WAF Content Package
// Installs WAF workbooks, analytics rules, and hunting queries into Sentinel
// ---------------------------------------------------------------------------
resource sentinelWafPackage 'Microsoft.SecurityInsights/contentPackages@2024-01-01-preview' = {
  scope: workspace
  name: 'azuresentinel.azure-sentinel-solution-azurewebapplicationfirewall'
  dependsOn: [sentinelOnboarding]
  properties: {
    contentId: 'azuresentinel.azure-sentinel-solution-azurewebapplicationfirewall'
    contentProductId: 'azuresentinel.azure-sentinel-solution-azurewebapplicationfirewall-sl-${uniqueString(workspaceId)}'
    displayName: 'Azure Web Application Firewall'
    contentKind: 'Solution'
    contentSchemaVersion: '3.0.0'
    version: '1.0.0'
    isNew: 'false'
    isPreview: 'false'
    isFeatured: 'false'
  }
}

// ---------------------------------------------------------------------------
// Sentinel Content Hub: Azure Network Security Content Package
// Installs network analytics workbooks and hunting queries into Sentinel
// ---------------------------------------------------------------------------
resource sentinelNetworkPackage 'Microsoft.SecurityInsights/contentPackages@2024-01-01-preview' = {
  scope: workspace
  name: 'azuresentinel.azure-sentinel-solution-networksession'
  dependsOn: [sentinelOnboarding]
  properties: {
    contentId: 'azuresentinel.azure-sentinel-solution-networksession'
    contentProductId: 'azuresentinel.azure-sentinel-solution-networksession-sl-${uniqueString(workspaceId)}'
    displayName: 'Network Session Essentials'
    contentKind: 'Solution'
    contentSchemaVersion: '3.0.0'
    version: '1.0.0'
    isNew: 'false'
    isPreview: 'false'
    isFeatured: 'false'
  }
}

// Reference existing workspace for Sentinel content scoping
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// ---------------------------------------------------------------------------
// Sentinel Onboarding State
// Required before content packages can be installed
// ---------------------------------------------------------------------------
resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2024-01-01-preview' = {
  scope: workspace
  name: 'default'
  properties: {}
}

// ---------------------------------------------------------------------------
// Sentinel Analytics Rule: WAF Block Events Detected
// Turns Front Door WAF blocks into real Sentinel incidents out-of-box.
// dependsOn sentinelOnboarding to avoid the workspace-onboarding race condition.
// ---------------------------------------------------------------------------
resource wafBlockAlertRule 'Microsoft.SecurityInsights/alertRules@2024-01-01-preview' = {
  scope: workspace
  name: guid(workspaceId, 'waf-block-events-rule')
  dependsOn: [sentinelOnboarding]
  kind: 'Scheduled'
  properties: {
    displayName: 'WAF Block Events Detected'
    description: 'Detects more than 5 Front Door WAF blocks in a 5-minute window for the same rule/client IP.'
    severity: 'Medium'
    enabled: true
    query: '''
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| summarize BlockCount = count() by bin(TimeGenerated, 5m), ruleName_s, clientIP_s
| where BlockCount > 5
| project TimeGenerated, ruleName_s, clientIP_s, BlockCount
'''
    queryFrequency: 'PT5M'
    queryPeriod: 'PT10M'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionEnabled: false
    suppressionDuration: 'PT5H'
    tactics: ['InitialAccess']
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: 'PT5H'
        matchingMethod: 'Selected'
        groupByEntities: ['IP']
      }
    }
    entityMappings: [
      {
        entityType: 'IP'
        fieldMappings: [
          { identifier: 'Address', columnName: 'clientIP_s' }
        ]
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Automation Rule: auto-triage incidents from the WAF block analytics rule
// Uses zero-config built-in actions only — no Logic App/playbook required.
// ---------------------------------------------------------------------------
resource wafAutomationRule 'Microsoft.SecurityInsights/automationRules@2024-01-01-preview' = {
  scope: workspace
  name: guid(workspaceId, 'waf-block-automation-rule')
  properties: {
    displayName: 'Auto-triage WAF block incidents'
    order: 1
    triggeringLogic: {
      isEnabled: true
      triggersOn: 'Incidents'
      triggersWhen: 'Created'
      conditions: [
        {
          conditionType: 'Property'
          conditionProperties: {
            propertyName: 'IncidentRelatedAnalyticRuleIds'
            operator: 'Contains'
            propertyValues: [wafBlockAlertRule.id]
          }
        }
      ]
    }
    actions: [
      {
        order: 1
        actionType: 'ModifyProperties'
        actionConfiguration: {
          labels: [
            { labelName: 'waf-auto-triage' }
          ]
        }
      }
      {
        order: 2
        actionType: 'AddIncidentTask'
        actionConfiguration: {
          title: 'Review WAF block incident'
          description: 'WAF blocked more than 5 requests from the same rule/client IP within a 5-minute window. Review the WAF Security Analytics workbook for this client IP before escalating.'
        }
      }
    ]
  }
}
