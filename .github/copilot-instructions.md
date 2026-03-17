# Copilot Instructions — Azure Front Door Sandbox

## Architecture
- **Azure Front Door Premium** with WAF, caching rules, and dual-origin failover
- **Azure Container Apps** (not App Service — VM quotas were 0 in the target subscription)
  - Origin A: `eastus2`, Origin B: `westus2`
  - Shared ACR for container image builds
- **Node.js 20 Express API** at `apps/api/` serving both API endpoints and static site
- **Bicep IaC** at `infra/bicep/` with modular structure (`main.bicep` + 7 modules)
- **Azure Developer CLI (azd)** configured via `azure.yaml` at repo root

## Critical Gotchas

### Front Door HttpsRedirect
Do NOT add a `UrlRedirect` rule inside a rule set when the route has `httpsRedirect: 'Enabled'`.
This causes the entire profile to get stuck at `deploymentStatus: NotStarted` and return 404s.
Use only the route-level `httpsRedirect` setting.

### WAF Lowercase Transform
When WAF custom rules use a `Lowercase` transform, it lowercases the **incoming request value** only — not the `matchValue`. So `matchValue` entries must already be lowercase for `Contains`/`Equal` operators to match.

### Front Door Propagation
Config changes (route creation, WAF policy updates, origin enable/disable) take **5–15 minutes** to propagate globally. WAF policy PUT requests can trigger full re-propagation and temporary 404s.

### Front Door Deletion
Front Door Premium profiles take **15–25 minutes** to delete. Resource group deletion will hang during this time — this is normal.

## Deploy & Destroy
```bash
azd up                     # Provisions infra + builds + deploys
azd down                   # Tears down all resources
```

## Running Tests
```bash
cd apps/api && npm test    # 6 unit tests (node:test, no extra deps)
```

## Key Prefixes & Defaults
- Prefix: `afdemo` (override via `DEMO_PREFIX` env var)
- Resource Group: `rg-afd-demo` (override via `DEMO_RG`)
- Regions: `eastus2` / `westus2` (override via `DEMO_LOCATION_A` / `DEMO_LOCATION_B`)
