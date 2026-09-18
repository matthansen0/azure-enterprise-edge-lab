using 'main.bicep'

param prefix = readEnvironmentVariable('DEMO_PREFIX', 'afdemo')
param locationA = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')
param locationB = readEnvironmentVariable('DEMO_LOCATION_B', 'westus2')
param wafMode = 'Prevention'
param rateLimitThreshold = 100
param logRetentionDays = 90
param deploySecurityCopilot = readEnvironmentVariable('DEPLOY_SECURITY_COPILOT', 'false')
