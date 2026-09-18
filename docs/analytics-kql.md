# Analytics KQL Queries

> Pre-built KQL queries for Azure Front Door monitoring via Log Analytics.
> These power the Azure Workbook dashboard and can be run ad-hoc in the portal.

---

## Traffic Overview

### Request Volume Over Time
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize RequestCount = count() by bin(TimeGenerated, 5m)
| render timechart
```

### Requests by HTTP Status Code
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize Count = count() by httpStatusCode_s
| sort by Count desc
| render piechart
```

### Top Requested URLs
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize Count = count() by requestUri_s
| top 20 by Count
```

### Requests by Client Country
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize Count = count() by clientCountry_s
| top 20 by Count
| render piechart
```

---

## Cache Performance

### Cache Hit/Miss Ratio
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize Count = count() by cacheStatus_s
| render piechart
```

### Cache Hit Rate Over Time
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize
    Total = count(),
    Hits = countif(cacheStatus_s == "HIT" or cacheStatus_s == "REMOTE_HIT" or cacheStatus_s == "PARTIAL_HIT")
  by bin(TimeGenerated, 5m)
| extend HitRate = round(100.0 * Hits / Total, 2)
| project TimeGenerated, HitRate
| render timechart
```

### Cache Miss URLs (Candidates for Caching)
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| where cacheStatus_s == "MISS"
| summarize MissCount = count() by requestUri_s
| top 20 by MissCount
```

---

## Latency

### Average and P95 Latency
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize
    AvgLatency = avg(todouble(timeTaken_s)),
    P50 = percentile(todouble(timeTaken_s), 50),
    P95 = percentile(todouble(timeTaken_s), 95),
    P99 = percentile(todouble(timeTaken_s), 99)
  by bin(TimeGenerated, 5m)
| render timechart
```

### Latency by Origin
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize AvgLatency = avg(todouble(timeTaken_s)), P95 = percentile(todouble(timeTaken_s), 95) by originName_s
| sort by AvgLatency asc
```

### Slow Requests (> 2s)
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| where todouble(timeTaken_s) > 2
| project TimeGenerated, requestUri_s, timeTaken_s, httpStatusCode_s, originName_s, cacheStatus_s
| sort by todouble(timeTaken_s) desc
| take 50
```

---

## WAF / Security

### WAF Actions Summary
```kql
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| summarize Count = count() by action_s, ruleName_s
| sort by Count desc
```

### WAF Blocks Over Time
```kql
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| summarize Blocks = count() by bin(TimeGenerated, 5m)
| render timechart
```

### WAF Blocks by Client IP
```kql
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| summarize Blocks = count() by clientIP_s
| top 20 by Blocks
```

### WAF Blocks by Rule Name
```kql
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| summarize Blocks = count() by ruleName_s
| sort by Blocks desc
```

### Rate Limit Events
```kql
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where ruleName_s contains "RateLimit"
| summarize Count = count() by action_s, bin(TimeGenerated, 1m)
| render timechart
```

### Bot Detection Summary
```kql
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where ruleName_s contains "Bot"
| summarize Count = count() by action_s, ruleName_s
| sort by Count desc
```

---

## Origin Health

> Front Door only logs **failed** health probes — there is no "success" row to compare against, so these queries only ever show failures. No rows means every probe in the time range succeeded.

### Health Probe Failures by Origin
```kql
AzureDiagnostics
| where Category == "FrontDoorHealthProbeLog"
| summarize FailedProbes = count() by originName_s
| render barchart
```

### Health Probe Failure Details
```kql
AzureDiagnostics
| where Category == "FrontDoorHealthProbeLog"
| project TimeGenerated, originName_s, result_s, httpStatusCode_s
| sort by TimeGenerated desc
| take 50
```

### Origin Response Time
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| where isnotempty(originName_s)
| summarize AvgOriginLatency = avg(todouble(timeTaken_s)) by originName_s, bin(TimeGenerated, 5m)
| render timechart
```

---

## Copilot in Log Analytics

`afdemo-law` > **Logs** opens a free, built-in Copilot chat pane by default. Ask it any of the questions above in plain language (e.g. "show WAF blocked requests by rule in the last hour") and it drafts and runs the KQL for you. This is separate from — and free unlike — the Security Copilot prompts below.

## Security Copilot Prompt Examples

> These are natural-language prompts you can type directly into Security Copilot.
> Copilot generates and runs the KQL for you against the connected Sentinel workspace.

### Investigate WAF Blocks
```
Show me all WAF block events from the last hour, grouped by source IP and rule name
```

### Identify Repeat Offenders
```
Which client IPs have been blocked by the WAF more than 10 times in the last 24 hours?
```

### Anomaly Detection
```
Are there any unusual traffic spikes or anomalous request patterns to /api/health in the last 6 hours?
```

### Rate Limit Analysis
```
How many requests were rate-limited in the last hour and from which IPs?
```

### Incident Summary
```
Summarize the latest Sentinel incident related to WAF blocks, including affected IPs and triggered rules
```

### Threat Intelligence Lookup
```
What threat intelligence do we have on the top 3 source IPs that triggered WAF blocks today?
```

---

## Operational

### Error Rate (4xx + 5xx)
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize
    Total = count(),
    Errors = countif(toint(httpStatusCode_s) >= 400)
  by bin(TimeGenerated, 5m)
| extend ErrorRate = round(100.0 * Errors / Total, 2)
| project TimeGenerated, ErrorRate
| render timechart
```

### Bandwidth (Bytes Transferred)
```kql
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize TotalBytes = sum(toint(responseSize_s)) by bin(TimeGenerated, 5m)
| render timechart
```
