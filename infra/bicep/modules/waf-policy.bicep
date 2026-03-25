// ---------------------------------------------------------------------------
// Module: WAF Policy for Azure Front Door Premium  (v2)
// ---------------------------------------------------------------------------
@description('Resource name prefix')
param prefix string

@description('Location')
param location string = 'global'

@description('WAF mode: Detection or Prevention')
@allowed(['Detection', 'Prevention'])
param mode string = 'Prevention'

@description('Rate limit threshold (requests per minute)')
param rateLimitThreshold int = 100

@description('Tags')
param tags object = {}

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: '${prefix}wafpolicy'
  location: location
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: mode
      requestBodyCheck: 'Enabled'
    }

    // --- Managed Rule Sets ---
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
        }
      ]
    }

    // --- Custom Rules ---
    customRules: {
      rules: [
        // Rule 1: Block requests with X-Demo-Block header (curl exercise)
        {
          name: 'BlockDemoHeader'
          priority: 100
          ruleType: 'MatchRule'
          action: 'Block'
          matchConditions: [
            {
              matchVariable: 'RequestHeader'
              selector: 'X-Demo-Block'
              operator: 'Equal'
              matchValue: [
                'true'
              ]
              transforms: [
                'Lowercase'
              ]
            }
          ]
        }
        // Rule 2: Block requests with ?waf-test=block query param (browser exercise)
        {
          name: 'BlockDemoQueryParam'
          priority: 150
          ruleType: 'MatchRule'
          action: 'Block'
          matchConditions: [
            {
              matchVariable: 'QueryString'
              operator: 'Contains'
              matchValue: [
                'waf-test=block'
              ]
              transforms: [
                'Lowercase'
              ]
            }
          ]
        }
        // Rule 3: Rate limit — block after N requests/minute per IP
        {
          name: 'RateLimitPerIP'
          priority: 200
          ruleType: 'RateLimitRule'
          action: 'Block'
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: rateLimitThreshold
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'RegEx'
              matchValue: [
                '.+'
              ]
            }
          ]
        }
        // Rule 4: Block suspicious bot-like User-Agent (curl exercise)
        {
          name: 'BlockDemoBotUA'
          priority: 300
          ruleType: 'MatchRule'
          action: 'Block'
          matchConditions: [
            {
              matchVariable: 'RequestHeader'
              selector: 'User-Agent'
              operator: 'Contains'
              matchValue: [
                'demomaliciousbot/1.0'
              ]
              transforms: [
                'Lowercase'
              ]
            }
          ]
        }
      ]
    }
  }
}

output wafPolicyId string = wafPolicy.id
output wafPolicyName string = wafPolicy.name
