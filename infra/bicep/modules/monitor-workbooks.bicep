// ---------------------------------------------------------------------------
// Module: Azure Monitor Workbooks for Front Door & WAF
// Creates gallery-ready workbooks that appear in Azure Monitor and
// in the Front Door blade under Analytics → Reports / Security Reports.
// ---------------------------------------------------------------------------
@description('Resource name prefix')
param prefix string

@description('Location')
param location string

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Tags')
param tags object = {}

// ---------------------------------------------------------------------------
// Workbook 1: Front Door Traffic Analytics
// Shows request volume, latency percentiles, cache hit ratio, origin health,
// error rate breakdown, geographic distribution — feeds AFD "Reports" blade.
// ---------------------------------------------------------------------------
resource trafficWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, '${prefix}-afd-traffic-workbook')
  location: location
  tags: union(tags, { 'hidden-title': '${prefix} Front Door Traffic Analytics' })
  kind: 'shared'
  properties: {
    displayName: '${prefix} Front Door Traffic Analytics'
    category: 'workbook'
    sourceId: workspaceId
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# Front Door Traffic Analytics\n---\nThis workbook provides traffic, latency, and cache analytics for the Azure Front Door Premium profile.'
          }
          name: 'header'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorAccessLog"\n| summarize Requests = count() by bin(TimeGenerated, 5m)\n| render timechart'
            size: 0
            title: 'Request Volume (5-min bins)'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'requestVolume'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorAccessLog"\n| summarize P50=percentile(todouble(timeTaken_s), 50), P95=percentile(todouble(timeTaken_s), 95), P99=percentile(todouble(timeTaken_s), 99) by bin(TimeGenerated, 5m)\n| render timechart'
            size: 0
            title: 'Latency Percentiles (P50, P95, P99)'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'latencyPercentiles'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorAccessLog"\n| extend IsHit = cacheStatus_s has "HIT"\n| summarize Total = count(), Hits = countif(IsHit) by bin(TimeGenerated, 5m)\n| extend HitRatio = round(100.0 * Hits / Total, 1)\n| project TimeGenerated, HitRatio\n| render timechart'
            size: 0
            title: 'Cache Hit Ratio (%)'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'cacheHitRatio'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorAccessLog"\n| summarize Count = count() by httpStatusCode_d\n| order by Count desc\n| render piechart'
            size: 0
            title: 'HTTP Status Code Distribution'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'statusCodes'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorAccessLog"\n| summarize Requests = count() by clientCountry_s\n| top 20 by Requests\n| render barchart'
            size: 0
            title: 'Top 20 Countries by Request Volume'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'geoDistribution'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorHealthProbeLog"\n| summarize HealthyCount = countif(httpStatusCode_d >= 200 and httpStatusCode_d < 400), UnhealthyCount = countif(httpStatusCode_d >= 400 or httpStatusCode_d == 0) by origin_s, bin(TimeGenerated, 5m)\n| render timechart'
            size: 0
            title: 'Origin Health Probe Results'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'originHealth'
        }
      ]
      isLocked: false
    })
  }
}

// ---------------------------------------------------------------------------
// Workbook 2: WAF Security Analytics
// Shows WAF actions, blocked requests, rule hit frequency, top attackers —
// feeds AFD "Security Reports" blade.
// ---------------------------------------------------------------------------
resource wafWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, '${prefix}-waf-security-workbook')
  location: location
  tags: union(tags, { 'hidden-title': '${prefix} WAF Security Analytics' })
  kind: 'shared'
  properties: {
    displayName: '${prefix} WAF Security Analytics'
    category: 'workbook'
    sourceId: workspaceId
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# WAF Security Analytics\n---\nThis workbook provides Web Application Firewall analytics including blocked requests, rule triggers, and attack sources.'
          }
          name: 'header'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorWebApplicationFirewallLog"\n| summarize Count = count() by action_s, bin(TimeGenerated, 5m)\n| render timechart'
            size: 0
            title: 'WAF Actions Over Time (Block / Allow / Log)'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'wafActions'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorWebApplicationFirewallLog"\n| where action_s == "Block"\n| summarize BlockedRequests = count() by bin(TimeGenerated, 5m)\n| render timechart'
            size: 0
            title: 'Blocked Requests Over Time'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'blockedRequests'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorWebApplicationFirewallLog"\n| where action_s == "Block"\n| summarize Count = count() by ruleName_s\n| top 10 by Count\n| render barchart'
            size: 0
            title: 'Top 10 WAF Rules Triggered (Blocked)'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'topRules'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorWebApplicationFirewallLog"\n| where action_s == "Block"\n| summarize Count = count() by clientIP_s\n| top 20 by Count\n| render barchart'
            size: 0
            title: 'Top 20 Blocked Source IPs'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'topBlockedIPs'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorWebApplicationFirewallLog"\n| summarize Count = count() by policyName_s, action_s\n| render barchart'
            size: 0
            title: 'WAF Policy Actions Summary'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'policyActions'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontDoorWebApplicationFirewallLog"\n| where action_s == "Block"\n| summarize Count = count() by clientCountry_s\n| top 10 by Count\n| render piechart'
            size: 0
            title: 'Blocked Requests by Country'
            timeContext: { durationMs: 86400000 }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [ workspaceId ]
          }
          name: 'blockedByCountry'
        }
      ]
      isLocked: false
    })
  }
}

output trafficWorkbookId string = trafficWorkbook.id
output wafWorkbookId string = wafWorkbook.id
