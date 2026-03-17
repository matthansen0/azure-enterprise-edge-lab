# Operating Model

## Overview

This document defines the operating model for the enterprise edge + security platform, including the RACI matrix, support tiers, SLA-backed incident flow, and escalation model.

---

## RACI Matrix

| Activity | Platform Team | Security (SecOps) | Application Team | Executive Sponsor |
|----------|:---:|:---:|:---:|:---:|
| **Edge/CDN Configuration** | R/A | C | I | I |
| **WAF Policy Management** | C | R/A | I | I |
| **Origin App Deployment** | C | I | R/A | I |
| **TLS Certificate Management** | R/A | C | I | I |
| **Cache Policy Design** | R | I | A/C | I |
| **Purge Operations** | R | I | A | I |
| **Security Incident Triage** | C | R/A | I | I |
| **DDoS Response** | R | A | I | C |
| **Sentinel Rule Authoring** | C | R/A | I | I |
| **SOC Alert Response** | I | R/A | C | I |
| **RBAC / Access Reviews** | C | R/A | I | A |
| **Capacity Planning** | R/A | I | C | I |
| **Vendor Management** | C | I | I | R/A |
| **Change Advisory Board** | R | R | R | A |
| **Compliance Audits** | C | R | C | A |

> **R** = Responsible, **A** = Accountable, **C** = Consulted, **I** = Informed

---

## Support Tiers

### Tier 0: Self-Service & Automation
- **Scope**: Automated monitoring, health probes, auto-failover, managed certificate renewal
- **Response**: Immediate (automated)
- **Examples**: Origin failover, cache purge API, automated WAF blocks

### Tier 1: Platform Operations
- **Scope**: Routine operations, configuration changes, user management
- **Response**: Within business hours
- **Team**: Platform Engineering / DevOps
- **Examples**: Add custom domain, update WAF rule, run purge

### Tier 2: Engineering & Security
- **Scope**: Complex issues, WAF tuning, performance optimization, security investigations
- **Response**: SLA-backed (see below)
- **Team**: Senior Platform Engineers + SecOps
- **Examples**: WAF false positive tuning, origin health investigation, Sentinel incident triage

### Tier 3: Architecture & Vendor Escalation
- **Scope**: Design changes, Azure platform issues, vendor escalation
- **Response**: SLA-backed (see below)
- **Team**: Solution Architects + Microsoft Support
- **Examples**: Architecture review, Azure service issue, capacity limits

---

## SLA-Backed Incident Response

### Severity Classification

| Severity | Definition | Example |
|----------|-----------|---------|
| **SEV 1** — Critical | Complete service outage; all users affected | Front Door endpoint down, all origins failed |
| **SEV 2** — High | Major functionality degraded; significant user impact | One origin down (failover active), high WAF block rate affecting legitimate traffic |
| **SEV 3** — Medium | Minor degradation; limited user impact | Elevated latency in one region, cache hit rate drop |
| **SEV 4** — Low | Informational; no immediate user impact | Scheduled maintenance, configuration request |

### Response & Resolution SLAs

| Severity | Acknowledge | First Response | Status Update | Target Resolution |
|----------|------------|----------------|---------------|-------------------|
| SEV 1 | 5 min | 15 min | Every 30 min | 4 hours |
| SEV 2 | 15 min | 30 min | Every 1 hour | 8 hours |
| SEV 3 | 1 hour | 4 hours | Every 4 hours | 24 hours |
| SEV 4 | 4 hours | 1 business day | As needed | 5 business days |

### Communication Channels

| Severity | Primary Channel | Secondary | Stakeholder Update |
|----------|----------------|-----------|-------------------|
| SEV 1 | War room (Teams) | Phone bridge | Executive email every 30 min |
| SEV 2 | Teams channel | Email | Manager email every 1 hour |
| SEV 3 | Teams channel | Ticket system | Ticket updates |
| SEV 4 | Ticket system | — | On resolution |

---

## Escalation Model

```
                Time=0        +15 min       +1 hour       +4 hours
SEV 1:    On-Call Eng → Team Lead → Dir. of Eng → VP/CTO
SEV 2:    On-Call Eng → Team Lead → Dir. of Eng
SEV 3:    Team Queue  → Assigned Eng → Team Lead
SEV 4:    Team Queue  → Assigned Eng
```

### Escalation Triggers

| Trigger | Action |
|---------|--------|
| SLA breach imminent | Auto-escalate to next tier |
| Customer request | Immediate escalation per customer severity |
| Security incident | Direct to SecOps team lead |
| Azure platform issue | Open Microsoft support ticket (Premier/Unified) |
| Repeated incident (>2 in 7 days) | Trigger problem management review |

---

## Operational Cadences

| Cadence | Frequency | Attendees | Purpose |
|---------|-----------|-----------|---------|
| Daily standup | Daily | Platform + SecOps | Incident review, pending changes |
| Change Advisory Board | Weekly | All teams | Approve configuration changes |
| Security Review | Bi-weekly | SecOps + Platform | WAF tuning, threat landscape |
| Performance Review | Monthly | Platform + App Teams | Latency, cache, capacity |
| Executive Review | Monthly | All + Exec Sponsor | KPIs, SLA compliance, roadmap |
| Disaster Recovery Drill | Quarterly | All teams | Failover test, runbook validation |

---

## Key Performance Indicators (KPIs)

| KPI | Target | Measurement |
|-----|--------|-------------|
| Platform Availability | ≥ 99.99% | Azure Monitor uptime checks |
| Cache Hit Ratio | ≥ 90% | Front Door access logs |
| P95 Latency (Edge) | < 100ms | Front Door access logs |
| WAF False Positive Rate | < 0.1% | WAF logs vs. legitimate traffic baseline |
| Mean Time to Detect | < 5 min | Sentinel incident creation time |
| Mean Time to Respond | < 15 min (SEV 1) | Incident management system |
| SLA Compliance | 100% | Incident post-mortem tracking |
| Change Success Rate | ≥ 98% | Change management records |
