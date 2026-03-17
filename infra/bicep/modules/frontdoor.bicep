// ---------------------------------------------------------------------------
// Module: Azure Front Door Premium Profile
// ---------------------------------------------------------------------------
@description('Resource name prefix')
param prefix string

@description('Origin A hostname')
param originAHostname string

@description('Origin B hostname')
param originBHostname string

@description('WAF Policy ID')
param wafPolicyId string

@description('Tags')
param tags object = {}

@description('Placeholder custom domains (for multi-subdomain demo config)')
param customDomainPrefixes array = ['www', 'api', 'cdn', 'portal']

@description('Base domain for placeholder custom domains')
param baseDomain string = 'demo.example.com'

// --- Front Door Profile ---
resource profile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: '${prefix}-afd'
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

// --- Front Door Endpoint ---
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: profile
  name: '${prefix}-endpoint'
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

// --- Origin Group (with failover) ---
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: profile
  name: 'default-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/api/health'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// --- Origin A (primary) ---
resource originA 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: 'origin-a'
  properties: {
    hostName: originAHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: originAHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// --- Origin B (secondary — failover) ---
resource originB 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: 'origin-b'
  properties: {
    hostName: originBHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: originBHostname
    priority: 2
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// --- Security Policy (WAF association) ---
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = {
  parent: profile
  name: 'waf-security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyId
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

// --- Rule Set for caching overrides ---
resource ruleSet 'Microsoft.Cdn/profiles/ruleSets@2024-02-01' = {
  parent: profile
  name: 'CachingRules'
}

// Rule: Honor origin TTL for /static/* paths (style.css=1y, version.json=30s)
resource staticCacheRule 'Microsoft.Cdn/profiles/ruleSets/rules@2024-02-01' = {
  parent: ruleSet
  name: 'OverrideStaticTTL'
  properties: {
    order: 1
    conditions: [
      {
        name: 'UrlPath'
        parameters: {
          typeName: 'DeliveryRuleUrlPathMatchConditionParameters'
          operator: 'BeginsWith'
          matchValues: [
            '/static/'
          ]
          transforms: [
            'Lowercase'
          ]
        }
      }
    ]
    actions: [
      {
        name: 'RouteConfigurationOverride'
        parameters: {
          typeName: 'DeliveryRuleRouteConfigurationOverrideActionParameters'
          cacheConfiguration: {
            queryStringCachingBehavior: 'IgnoreQueryString'
            cacheBehavior: 'HonorOrigin'
            isCompressionEnabled: 'Enabled'
          }
        }
      }
    ]
  }
}

// Rule: Respect origin for /api/* paths
resource apiCacheRule 'Microsoft.Cdn/profiles/ruleSets/rules@2024-02-01' = {
  parent: ruleSet
  name: 'RespectOriginApiCache'
  properties: {
    order: 2
    conditions: [
      {
        name: 'UrlPath'
        parameters: {
          typeName: 'DeliveryRuleUrlPathMatchConditionParameters'
          operator: 'BeginsWith'
          matchValues: [
            '/api/'
          ]
          transforms: [
            'Lowercase'
          ]
        }
      }
    ]
    actions: [
      {
        name: 'RouteConfigurationOverride'
        parameters: {
          typeName: 'DeliveryRuleRouteConfigurationOverrideActionParameters'
          cacheConfiguration: {
            queryStringCachingBehavior: 'UseQueryString'
            cacheBehavior: 'HonorOrigin'
            isCompressionEnabled: 'Enabled'
          }
        }
      }
    ]
  }
}

// Note: HTTPS redirect is handled by the route-level httpsRedirect: 'Enabled' setting.
// Do NOT add a separate UrlRedirect rule here — it conflicts and prevents deployment.

// --- Route ---
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'default-route'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    ruleSets: [
      {
        id: ruleSet.id
      }
    ]
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    httpsRedirect: 'Enabled'
    linkToDefaultDomain: 'Enabled'
    cacheConfiguration: {
      queryStringCachingBehavior: 'UseQueryString'
      compressionSettings: {
        isCompressionEnabled: true
        contentTypesToCompress: [
          'text/html'
          'text/css'
          'application/javascript'
          'application/json'
          'image/svg+xml'
          'text/plain'
        ]
      }
    }
  }
  dependsOn: [
    originA
    originB
    securityPolicy
    staticCacheRule
    apiCacheRule
  ]
}

// --- Outputs ---
output profileName string = profile.name
output profileId string = profile.id
output endpointName string = endpoint.name
output endpointHostName string = endpoint.properties.hostName
output originGroupName string = originGroup.name
output customDomainConfig array = [for (cdp, i) in customDomainPrefixes: {
  subdomain: '${cdp}.${baseDomain}'
  note: 'Placeholder — configure DNS CNAME to ${endpoint.properties.hostName}'
}]
