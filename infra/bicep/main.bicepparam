using 'main.bicep'

param prefix = 'afdemo'
param locationA = 'eastus2'
param locationB = 'westus2'
param wafMode = 'Prevention'
param rateLimitThreshold = 100
param logRetentionDays = 90
