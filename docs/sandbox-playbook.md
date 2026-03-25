# Demo Runbook

> Step-by-step walkthrough of the CDN + WAF sandbox.
> Each section references exact commands and expected output.

---

## Pre-Demo Checklist

- [ ] Dev Container running with all tools installed
- [ ] Logged in: `azd auth login --use-device-code` and `az login --use-device-code`
- [ ] Subscription set: `az account set --subscription "<ID>"`
- [ ] Environment deployed: `azd up`
- [ ] Browser tabs open: Azure Portal (Front Door, WAF, Sentinel, Workbook), Front Door endpoint URL

---

## Section A: Core Capabilities

### A1. Platform Overview & Architecture

Walk through the architecture diagram, global anycast network, and multi-region origin failover design.

**Steps**:
1. Show [docs/architecture.md](architecture.md) diagram
2. Open Azure Portal → Front Door profile → Overview blade
3. Show the endpoint, origin group, and routing rules

**Expected Output**: Portal shows the Front Door profile with Premium SKU, endpoint, and configured origin group with two origins.

---

### A2. Live CDN Delivery Demo

**Steps**:
```bash
# Fetch homepage through Front Door
curl -sI "https://$(az afd endpoint show --resource-group rg-afd-demo \
  --profile-name afdemo-afd --endpoint-name afdemo-endpoint \
  --query hostName -o tsv)/" | head -20
```

**Expected Output**:
- `HTTP/2 200`
- `cache-control: public, max-age=300`
- `x-cache: TCP_HIT` or `TCP_MISS` (depends on first request)
- `strict-transport-security` header present

```bash
# Show static asset caching
curl -sI "https://$AFD_ENDPOINT/static/style.css" | grep -i "cache-control\|x-cache\|age"
```

**Expected Output**: `cache-control: public, max-age=31536000, immutable`, `x-cache: TCP_HIT`

```bash
# Show API no-cache behavior
curl -s "https://$AFD_ENDPOINT/api/health" | jq .
```

**Expected Output**: JSON with `status: "healthy"`, `region`, `timestamp`

---

### A3. Cache Override & TTL Policies

**Steps**:
1. In Azure Portal → Front Door → Rules Engine → "CachingRules" rule set
2. Show two rules: OverrideStaticTTL (overrides to 1 day) and RespectOriginApiCache (honors origin)

```bash
# API endpoint with configurable cache
curl -sI "https://$AFD_ENDPOINT/api/cache-control?maxage=120" | grep -i cache-control
# Expected: cache-control: public, max-age=120

curl -sI "https://$AFD_ENDPOINT/api/cache-control?policy=no-store" | grep -i cache-control
# Expected: cache-control: no-store
```

---

### A4. Instant Purge Demo

**Steps**:
```bash
bash scripts/purge.sh /static/version.json
```

**Expected Output**:
- Before purge: `age: <some value>`, `x-cache: TCP_HIT`
- After purge: `age: 0` or missing, `x-cache: TCP_MISS`

```bash
# Bulk purge
az afd endpoint purge --resource-group rg-afd-demo \
  --profile-name afdemo-afd --endpoint-name afdemo-endpoint \
  --content-paths "/static/*"
```

---

### A5. Content Deployment Workflow

Demonstrates how a code change reaches the edge.

**Steps**:
1. Make a change to the app (e.g., update `version.json`)
2. Redeploy: `azd deploy`
3. Purge the edge cache: `bash scripts/purge.sh /static/version.json`
4. Verify the new version is live at the edge

**Expected Output**: Updated content visible through Front Door after deploy + purge.

---

### A6. TLS & Certificate Management

**Steps**:
1. Show [docs/tls-certificate-management.md](tls-certificate-management.md)
2. In Portal → Front Door → Custom Domains → show managed certificate option
3. Explain managed vs. BYOC (Bring Your Own Certificate) via Key Vault

**Expected Output**: Documentation walkthrough; no live cert changes needed.

---

### A7. Multi-Subdomain & User Management

**Steps**:
1. Show Front Door deployment output: `customDomainConfig` (4 placeholder subdomains)
2. In Portal → Resource Group → Access Control (IAM) → show how roles would be assigned
3. Reference [docs/operating-model.md](operating-model.md) RACI section

**Expected Output**: Configuration shows www/api/cdn/portal subdomains. IAM blade open for role assignment demo.

---

## Section B: Security

### B1. WAF Overview & Managed Rules

**Steps**:
1. Portal → Front Door → WAF Policy → Managed Rules
2. Show DefaultRuleSet 2.1 and BotManagerRuleSet 1.1 enabled

---

### B2. WAF Custom Rule — Header Block

**Steps**:
```bash
# Normal request — should succeed
curl -s -o /dev/null -w "HTTP %{http_code}\n" "https://$AFD_ENDPOINT/api/health"
# Expected: HTTP 200

# Request with blocking header — should be blocked
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -H "X-Demo-Block: true" "https://$AFD_ENDPOINT/api/health"
# Expected: HTTP 403
```

**Expected Output**: First request returns 200, second returns 403.

---

### B3. WAF Bot Management

**Steps**:
```bash
# Request with suspicious user agent
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -A "DemoMaliciousBot/1.0" "https://$AFD_ENDPOINT/api/health"
# Expected: HTTP 403
```

---

### B4. Rate Limiting Demo

**Steps**:
```bash
bash scripts/generate-traffic.sh 150 10
```

**Expected Output**: First ~100 requests succeed (HTTP 200), remaining get HTTP 429 or 403 (rate limited).

---

### B5. Origin Failover Demo

**Steps**:
```bash
# Check current origin
curl -s "https://$AFD_ENDPOINT/api/health" | jq .region

# Disable Origin B
bash scripts/toggle-failover.sh disable origin-b

# Verify still healthy (Origin A serving)
curl -s "https://$AFD_ENDPOINT/api/health" | jq .region

# Re-enable Origin B
bash scripts/toggle-failover.sh enable origin-b
```

**Expected Output**: Health endpoint continues responding. Region value confirms which origin is serving.

---

### B6. DDoS Protection

**Steps**:
1. Show [docs/architecture.md](architecture.md) §9 DDoS section
2. Portal → Front Door → review built-in L3/L4 mitigation
3. Azure DDoS Network Protection is available for VNet-level resources

---

## Section C: Innovation & Intelligent Automation

### C1. Analytics & KQL Queries

**Steps**:
1. Portal → Log Analytics → run KQL queries from [docs/analytics-kql.md](analytics-kql.md)
2. Open the deployed Azure Workbook dashboard

```bash
# Quick log query via CLI
az monitor log-analytics query \
  -w "$(az monitor log-analytics workspace show -g rg-afd-demo -n afdemo-law --query customerId -o tsv)" \
  --analytics-query "AzureDiagnostics | where Category == 'FrontDoorAccessLog' | summarize count() by httpStatusCode_s | sort by count_ desc" \
  --output table
```

---

### C2. SOC / Sentinel Integration

**Steps**:
1. Portal → Microsoft Sentinel → select the `afdemo-law` workspace
2. Show the Sentinel workspace overview (the solution is deployed via Bicep)
3. Walk through creating an analytics rule: Analytics → Create → Scheduled query rule
4. Show [docs/soc-automation-stub.md](soc-automation-stub.md) for automation workflow

**Expected Output**: Sentinel workspace active, ready for rule creation and incident management.

---

### C3. Security Copilot — AI-Assisted SOC (Live)

**Pre-req**: Security Copilot SCU capacity is deployed automatically by `azd up` (1 SCU, pay-as-you-go ~$4/hr).

**Steps**:

1. **Open Security Copilot in Portal**
   - Azure Portal → Microsoft Security Copilot (or open the embedded pane inside Sentinel)

2. **Natural Language KQL — Live Query**
   Type this prompt into Copilot:
   > *"Show me all WAF block events from the last hour, grouped by source IP and rule name"*

   Copilot generates and runs KQL against the Sentinel workspace. Compare its output with the manual query in [docs/analytics-kql.md](analytics-kql.md).

3. **Incident Summarization**
   - If a Sentinel incident exists from the WAF block demo (Section B2/B3), ask:
   > *"Summarize the latest Sentinel incident related to WAF blocks"*
   - Copilot returns a plain-language summary with affected IPs, triggered rules, timeline, and severity assessment.

4. **Threat Intelligence Lookup**
   - Pick a source IP from the WAF logs and ask:
   > *"What do we know about this IP? Check threat intelligence."*
   - Copilot correlates against Microsoft Threat Intelligence and flags reputation, geo, and known campaigns.

5. **Guided Response Recommendation**
   - Ask:
   > *"What response actions do you recommend for this incident?"*
   - Copilot suggests: block IP in WAF, create a custom rule, escalate to Tier 2, or close as expected traffic.

Security Copilot is deployed as infrastructure alongside Sentinel — same `azd up`, same resource group, same teardown. Pay-as-you-go with no per-user licenses.

**Expected Output**: Live Copilot responses showing KQL generation, incident summary, and TI enrichment against real WAF log data.

---

## Section D: Additional Resources

### D1. Migration & Onboarding

See [docs/migration-onboarding.md](migration-onboarding.md) for the full phased migration plan:
assessment → parallel run → DNS cutover → validation → decommission

---

### D2. Operating Model & SLA

See [docs/operating-model.md](operating-model.md) for:
RACI matrix, support tiers, SLA-backed response times, escalation path

---

### D3. Future Enhancements

Potential additions to this sandbox:
- Private Link origins
- Azure Policy governance
- Logic App playbook automation

---

## Teardown

```bash
azd down
```

Confirm resource deletion is initiated. Front Door profiles take 15–25 minutes to fully delete.
