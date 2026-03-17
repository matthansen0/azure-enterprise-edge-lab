// ---------------------------------------------------------------------------
// Module: Azure Workbook (Dashboard) for Front Door Monitoring
// ---------------------------------------------------------------------------
@description('Resource name prefix')
param prefix string

@description('Location')
param location string

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Tags')
param tags object = {}

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, '${prefix}-afd-workbook')
  location: location
  tags: union(tags, { 'hidden-title': '${prefix} Front Door CDN WAF Dashboard' })
  kind: 'shared'
  properties: {
    displayName: '${prefix} Front Door CDN WAF Dashboard'
    category: 'workbook'
    sourceId: workspaceId
    serializedData: loadTextContent('../../../dashboards/workbook-template.json')
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.name
