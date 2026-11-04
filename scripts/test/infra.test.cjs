const { test } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { execFileSync } = require("node:child_process");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const template = JSON.parse(execFileSync("az", [
  "bicep", "build", "--file", path.join(root, "infra/bicep/main.bicep"), "--stdout",
], { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 }));

function resources(template) {
  return template.resources.flatMap((resource) => [
    resource,
    ...(resource.type === "Microsoft.Resources/deployments" && resource.properties.template
      ? resources(resource.properties.template) : []),
  ]);
}

const all = resources(template);
const ofType = (type) => all.filter((resource) => resource.type === type);

test("Front Door uses route-level redirect, never a rule-set redirect action", () => {
  const routes = ofType("Microsoft.Cdn/profiles/afdEndpoints/routes");
  assert.equal(routes.length, 1);
  assert.equal(routes[0].properties.httpsRedirect, "Enabled");
  assert.equal(routes[0].properties.forwardingProtocol, "HttpsOnly");
  const rules = ofType("Microsoft.Cdn/profiles/ruleSets/rules");
  assert.equal(rules.length, 2);
  assert.ok(rules.every((rule) => rule.properties.actions.every((action) => action.name !== "UrlRedirect")));
});

test("both origins retain ordered failover and a non-cached health probe", () => {
  const origins = ofType("Microsoft.Cdn/profiles/originGroups/origins");
  assert.deepEqual(origins.map((origin) => origin.properties.priority).sort(), [1, 2]);
  assert.ok(origins.every((origin) => origin.properties.enabledState === "Enabled" && origin.properties.enforceCertificateNameCheck));
  assert.equal(ofType("Microsoft.Cdn/profiles/originGroups")[0].properties.healthProbeSettings.probePath, "/api/health");
});

test("WAF demo match values are lowercase when the request is lowercased", () => {
  const policies = ofType("Microsoft.Network/FrontDoorWebApplicationFirewallPolicies");
  assert.equal(policies.length, 1);
  const rules = policies[0].properties.customRules.rules;
  assert.equal(rules.length, 4);
  for (const rule of rules) {
    for (const condition of rule.matchConditions) {
      if (condition.transforms?.includes("Lowercase")) {
        assert.ok(condition.matchValue.every((value) => value === value.toLowerCase()), rule.name);
      }
    }
  }
});

test("Security Copilot remains opt-in and container base image remains digest-pinned", () => {
  assert.equal(template.parameters.deploySecurityCopilot.defaultValue, "false");
  const capacityModule = all.find((resource) => resource.name === "security-copilot");
  assert.ok(capacityModule?.condition);
  const dockerfile = readFileSync(path.join(root, "apps/Dockerfile"), "utf8");
  assert.match(dockerfile, /^FROM node:24-alpine@sha256:[a-f0-9]{64}$/m);
});

test("Sentinel's enabled WAF rule provides its schema before first log ingestion", () => {
  const rules = ofType("Microsoft.SecurityInsights/alertRules");
  assert.equal(rules.length, 1);
  const rule = rules[0];
  assert.equal(rule.properties.enabled, true);
  assert.match(rule.properties.query, /union isfuzzy=true AzureDiagnostics, \(datatable\(/);
  for (const column of ["TimeGenerated:datetime", "ResourceProvider:string", "Category:string", "action_s:string", "ruleName_s:string", "clientIP_s:string"]) {
    assert.ok(rule.properties.query.includes(column), column);
  }
  assert.match(rule.properties.query, /\| where BlockCount > 5/);
  assert.match(rule.properties.query, /bin\(TimeGenerated, 5m\), ruleName_s, clientIP_s/);
  assert.equal(rule.properties.entityMappings[0].fieldMappings[0].columnName, "clientIP_s");
  const doc = readFileSync(path.join(root, "docs/soc-automation-stub.md"), "utf8");
  const documentedQuery = doc.match(/```kql\n([\s\S]*?)\n```/)[1];
  assert.equal(rule.properties.query.trim(), documentedQuery.trim());
});
