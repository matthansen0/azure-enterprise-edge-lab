// ---------------------------------------------------------------------------
// Module: Microsoft Security Copilot — Pay-as-you-go (SCU Capacity)
// Provisions a minimum Security Compute Unit capacity for the demo.
// Billing: ~$4/hour per SCU while provisioned. Destroy with `azd down`.
// ---------------------------------------------------------------------------
@description('Resource name prefix')
param prefix string

@description('Location for the Security Copilot capacity')
param location string

@description('Number of Security Compute Units (minimum 1)')
@minValue(1)
param numberOfUnits int = 1

@description('Allow cross-geo compute for overflow')
@allowed(['Allowed', 'NotAllowed'])
param crossGeoCompute string = 'NotAllowed'

@description('Geo for data residency (US, EU, UK, ANZ)')
@allowed(['US', 'EU', 'UK', 'ANZ'])
param geo string = 'US'

@description('Tags')
param tags object = {}

resource securityCopilot 'Microsoft.SecurityCopilot/capacities@2023-12-01-preview' = {
  name: '${prefix}-seccopilot'
  location: location
  tags: tags
  properties: {
    numberOfUnits: numberOfUnits
    crossGeoCompute: crossGeoCompute
    geo: geo
  }
}

output capacityName string = securityCopilot.name
output capacityId string = securityCopilot.id
