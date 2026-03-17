// ---------------------------------------------------------------------------
// Module: Azure Container Registry (shared by both origins)
// ---------------------------------------------------------------------------
@description('Resource name prefix')
param prefix string

@description('Location for the ACR')
param location string

@description('Tags')
param tags object = {}

var acrName = '${prefix}acr${uniqueString(resourceGroup().id)}'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: take(acrName, 50)
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output acrId string = acr.id
