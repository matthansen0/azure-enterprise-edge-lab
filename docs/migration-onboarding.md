# Migration & Onboarding Plan

## Overview

This document outlines the phased approach for migrating from an existing CDN/WAF platform to the Azure Front Door Premium solution, including test plans, rollback procedures, and DNS cutover strategy.

---

## Phase 0: Assessment & Discovery (Weeks 1–2)

### Activities
1. **Current state audit**
   - Inventory all domains, subdomains, and associated certificates
   - Document existing CDN configuration (TTLs, caching rules, custom headers)
   - Map WAF rules and exclusions
   - Collect baseline traffic metrics (RPS, bandwidth, latency percentiles)
   - Identify file transfer workflows

2. **Dependency mapping**
   - Origin servers and health check configurations
   - DNS records (CNAME, A, AAAA) and TTL values
   - Client-side dependencies (hardcoded URLs, API base paths)
   - Third-party integrations (monitoring, alerting, ticketing)

3. **Risk assessment**
   - Identify high-traffic / high-sensitivity domains
   - Define migration order (low-risk first)
   - Document rollback criteria and triggers

### Deliverables
- [ ] Current state documentation
- [ ] Domain/subdomain inventory
- [ ] Migration order (prioritized list)
- [ ] Risk register

---

## Phase 1: Parallel Build (Weeks 3–4)

### Activities
1. **Deploy Azure infrastructure** (IaC — this repo)
   - Front Door profile, WAF policy, origins, Log Analytics, Sentinel
   - Storage accounts as needed

2. **Configure WAF policy**
   - Start in **Detection** mode (log only, no blocking)
   - Import/recreate custom rules from existing platform
   - Enable managed rule sets

3. **Configure origins**
   - Deploy application code to both origin App Services
   - Validate health probes are passing
   - Confirm origin access restrictions (Front Door service tag only)

4. **Configure caching rules**
   - Match existing TTL policies
   - Implement override rules in Rules Engine

### Deliverables
- [ ] Azure environment deployed and verified
- [ ] WAF in Detection mode with logs flowing to Log Analytics
- [ ] All origins healthy

---

## Phase 2: Shadow / Parallel Run (Weeks 5–6)

### Activities
1. **Shadow traffic testing**
   - Route a percentage of traffic to Azure Front Door using DNS weighted routing
   - Compare response times, cache behavior, and error rates between old and new
   - Monitor WAF Detection logs for false positives

2. **Functional testing**
   - Verify all endpoints return expected responses
   - Test cache hits/misses against expectations
   - Validate TLS certificates (managed or BYOC)
   - Test purge operations
   - Test end-to-end content delivery flows

3. **WAF tuning**
   - Review Detection logs for false positives
   - Create rule exclusions as needed
   - Validate custom rules trigger as expected

4. **Performance benchmarking**
   - Compare P50/P95/P99 latency
   - Compare cache hit ratios
   - Compare origin load

### Test Plan

| Test | Method | Expected Result | Pass Criteria |
|------|--------|-----------------|---------------|
| Homepage delivery | curl / browser | HTTP 200, correct content | < 200ms P95 |
| API health check | curl /api/health | JSON response with status | < 100ms P95 |
| Static asset caching | curl + check x-cache | TCP_HIT on second request | Hit ratio > 90% |
| Cache purge | purge.sh script | Cache miss after purge | x-cache: MISS |
| WAF block (header) | curl -H "X-Demo-Block: true" | HTTP 403 | Blocked |
| Rate limiting | generate-traffic.sh | 429 after threshold | Blocks above 100/min |
| Origin failover | toggle-failover.sh | Continued service | No downtime |

| TLS enforcement | curl http:// | 301 redirect to HTTPS | Redirect |

### Deliverables
- [ ] Shadow run report (comparison metrics)
- [ ] WAF tuning log (exclusions applied)
- [ ] Performance benchmark results
- [ ] Functional test results (all pass)

---

## Phase 3: DNS Cutover (Week 7)

### Pre-Cutover Checklist
- [ ] All functional tests passing
- [ ] WAF switched to **Prevention** mode
- [ ] Performance within acceptance criteria
- [ ] Certificates validated for all custom domains
- [ ] Runbook reviewed by operations team
- [ ] Rollback procedure documented and rehearsed
- [ ] Stakeholder sign-off obtained

### Cutover Procedure

1. **Lower DNS TTL** (48 hours before cutover)
   - Reduce CNAME TTL to 60 seconds for quick rollback ability
   
2. **Switch DNS** (maintenance window)
   ```
   # For each custom domain:
   # Old: www.example.com CNAME old-cdn.provider.com
   # New: www.example.com CNAME <prefix>-endpoint-<hash>.azurefd.net
   ```

3. **Monitor** (first 2 hours)
   - Watch Front Door access logs for traffic arriving
   - Verify cache hit ratios climbing
   - Monitor WAF logs for unexpected blocks
   - Check origin health probes
   - Validate error rates are within baseline

4. **Validate** (first 24 hours)
   - Full test plan re-execution
   - Stakeholder spot-checks
   - Performance comparison vs. baseline

5. **Restore DNS TTL** (after 48 hours stable)
   - Increase CNAME TTL back to standard (3600s or higher)

### Rollback Procedure

**Trigger criteria**: Any of the following within first 48 hours:
- Error rate > 2x baseline
- P95 latency > 2x baseline
- WAF blocking legitimate traffic that cannot be resolved with rule exclusions
- Origin health probe failures on both origins

**Rollback steps**:
1. Revert DNS CNAME to previous CDN provider
2. DNS propagation (< 60 seconds due to low TTL)
3. Verify traffic returning to old platform
4. Post-mortem: document issue and remediation plan

---

## Phase 4: Validation & Optimization (Weeks 8–9)

### Activities
1. **Post-cutover validation**
   - 7-day performance comparison vs. pre-migration baseline
   - WAF false positive review and final tuning
   - Cache optimization (identify new caching opportunities)

2. **Operational handover**
   - Train operations team on Front Door management
   - Deploy monitoring dashboards (Azure Workbook)
   - Configure Sentinel alerts and automation

3. **Documentation update**
   - Update runbooks with new procedures
   - Update architecture diagrams
   - Document WAF rule inventory

### Deliverables
- [ ] Post-migration performance report
- [ ] Operations team training completed
- [ ] Updated runbooks and documentation
- [ ] Sentinel monitoring active

---

## Phase 5: Decommission Legacy (Week 10+)

### Activities
1. Confirm zero traffic to old platform (7+ days)
2. Remove old DNS records
3. Cancel/decommission legacy CDN/WAF services
4. Archive old configuration for reference
5. Close migration project

### Deliverables
- [ ] Legacy platform decommissioned
- [ ] Migration project closed
- [ ] Lessons learned documented
