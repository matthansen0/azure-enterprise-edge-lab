# SOC Automation Stub

## Overview

This document describes the Sentinel automation workflow that would be deployed for production SOC integration. In this demo environment, the automation is represented as a skeleton — the Logic App and notification connectors are described but not fully deployed to avoid requiring external service credentials.

---

## Architecture

```
WAF Block Events → Sentinel Analytics Rule → Sentinel Incident
                                                    │
                                                    ▼
                                            Automation Rule
                                                    │
                                                    ▼
                                           Logic App Playbook
                                            ┌──────┴──────┐
                                            │             │
                                       Teams Channel  Email Alert
                                       Notification   (SOC Team)
```

## Sentinel Analytics Rule (Deployed)

**Name**: WAF Block Events Detected

- **Query Frequency**: Every 5 minutes
- **Lookback**: 10 minutes
- **Trigger**: >5 WAF blocks in a 5-minute window
- **Severity**: Medium
- **Tactic**: Initial Access

```kql
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| summarize BlockCount = count() by bin(TimeGenerated, 5m), ruleName_s, clientIP_s
| where BlockCount > 5
```

## Logic App Playbook (Skeleton)

The following Logic App would be created for production:

### Trigger
- **Type**: Microsoft Sentinel Incident trigger
- **Condition**: When a new incident is created by the "WAF Block Events Detected" rule

### Actions

1. **Parse Incident Details**
   - Extract: incident title, severity, rule name, client IP, block count

2. **Enrich with Threat Intelligence**
   - Query Microsoft Threat Intelligence for the source IP
   - Add enrichment data as incident comment

3. **Notify Teams Channel**
   - Post adaptive card to `#security-alerts` channel
   - Include: incident summary, severity badge, source IP, rule triggered
   - Action buttons: "View in Sentinel", "Block IP (confirm)"

4. **Send Email Alert**
   - To: `soc-team@organization.com`
   - Subject: `[Sentinel] WAF Alert: {incident.title}`
   - Body: HTML formatted incident summary with links

5. **Update Incident**
   - Add automation tag: `auto-notified`
   - Add comment: notification timestamp and channels notified

### Bicep Skeleton (Not Deployed)

```bicep
// This would deploy the Logic App — not included in demo to avoid external dependencies
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: '${prefix}-waf-alert-playbook'
  location: location
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          // Sentinel incident trigger configuration
        }
      }
      actions: {
        Parse_Incident: { /* ... */ }
        Post_to_Teams: { /* ... */ }
        Send_Email: { /* ... */ }
        Update_Incident: { /* ... */ }
      }
    }
  }
}
```

---

## Security Copilot Integration (Deployed)

### Overview

Microsoft Security Copilot is provisioned in this demo environment using the **pay-as-you-go** model (Security Compute Units). This removes the need for per-user licenses and bills only for consumed capacity (~$4/hour per SCU while provisioned).

The Bicep module at `infra/bicep/modules/security-copilot.bicep` deploys a minimum 1-SCU capacity that is automatically torn down with `azd down`.

### How It Connects to the SOC Workflow

```
WAF Block Events → Sentinel Incident → Security Copilot (AI triage)
                                              │
                                   ┌──────────┴──────────┐
                                   │                     │
                            Natural-language         Automated
                            incident summary      enrichment &
                            & recommended          threat intel
                            response actions        correlation
```

### Capabilities Available in This Demo

1. **Natural Language KQL** — Ask questions in plain English and Security Copilot generates and runs KQL against the Sentinel workspace:
   - *"Show me all WAF blocks from the last hour grouped by source IP"*
   - *"Which client IPs triggered the most rate-limit violations today?"*
   - *"Are there any anomalous traffic patterns to /api/health?"*

2. **Incident Summarization** — When Sentinel creates an incident from WAF block events, Security Copilot can auto-generate a plain-language summary including affected IPs, triggered rules, and timeline.

3. **Threat Intelligence Enrichment** — Source IPs from WAF blocks are automatically correlated against Microsoft Threat Intelligence to flag known-bad actors.

4. **Guided Response** — Copilot suggests response actions (block IP in WAF, escalate, notify SOC) based on the incident context and organizational playbooks.

### Portal Walkthrough

1. **Azure Portal → Security Copilot** — Open the standalone experience or the embedded pane in Sentinel
2. **Try a prompt**: `Summarize the latest Sentinel incidents related to WAF blocks`
3. **Generate KQL**: `Write a KQL query showing WAF block events by rule name over the last 24 hours`
4. **Investigate an IP**: `What do we know about IP 203.0.113.42? Check threat intelligence.`

### Billing Notes

| Model | How It Works | Cost |
|-------|-------------|------|
| **Pay-as-you-go (this demo)** | 1 SCU provisioned via Bicep; billed hourly while capacity exists | ~$4/hr per SCU |
| **Consumption (alternative)** | No capacity resource; billed per prompt/session | Usage-based |

> **Tip**: Run `azd down` after the demo to stop billing immediately. The 1-SCU capacity costs ~$96/day if left running.

## Integration Points

| System | Integration Method | Status |
|--------|-------------------|--------|
| Microsoft Sentinel | Native (deployed) | ✅ Active |
| Microsoft Teams | Logic App connector | 🔲 Skeleton |
| Email (Exchange/SMTP) | Logic App connector | 🔲 Skeleton |
| ServiceNow | Logic App connector | 🔲 Planned |
| PagerDuty | Logic App connector | 🔲 Planned |
| Slack | Logic App connector | 🔲 Planned |

## Production Deployment Steps

1. Deploy Logic App from the Bicep skeleton above
2. Authorize API connections (Teams, Office 365)
3. Create Sentinel Automation Rule linking the analytics rule to the playbook
4. Test with a safe WAF block trigger (`curl -H "X-Demo-Block: true"`)
5. Verify notification delivery in Teams and email
6. Configure SOC runbook for incident triage workflow
