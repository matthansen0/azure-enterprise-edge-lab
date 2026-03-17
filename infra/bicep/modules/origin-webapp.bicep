// ---------------------------------------------------------------------------
// Module: Origin Container App (Azure Container Apps — Node.js)
// ---------------------------------------------------------------------------
@description('Resource name prefix')
param prefix string

@description('Location for this origin')
param location string

@description('Origin label (e.g., a, b)')
param originLabel string

@description('azd service name for deployment targeting')
param serviceName string = ''

@description('ACR login server (e.g., myacr.azurecr.io)')
param acrLoginServer string = ''

@description('ACR resource name')
param acrName string = ''

@description('Tags')
param tags object = {}

var envName = '${prefix}-cae-${originLabel}'
var appName = '${prefix}-origin-${originLabel}'

// --- Container Apps Environment ---
resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  tags: tags
  properties: {}
}

// Reference existing ACR for admin credentials
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// --- Container App with quickstart image (updated with real code post-deploy) ---
var azdTag = empty(serviceName) ? {} : { 'azd-service-name': serviceName }
var registries = [
  {
    server: acrLoginServer
    username: acr.listCredentials().username
    passwordSecretRef: 'acr-password'
  }
]
var secrets = [
  {
    name: 'acr-password'
    value: acr.listCredentials().passwords[0].value
  }
]

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: union(tags, { originLabel: originLabel }, azdTag)
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      secrets: secrets
      registries: registries
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'api'
          image: 'mcr.microsoft.com/k8se/quickstart:latest'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'PORT'
              value: '8080'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

output appName string = containerApp.name
output hostname string = containerApp.properties.configuration.ingress.fqdn
output appId string = containerApp.id
output environmentName string = cae.name
