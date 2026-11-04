import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const workspace = process.env.SMOKE_WORKSPACE_ID;
assert.match(workspace ?? "", /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i, "SMOKE_WORKSPACE_ID must be the Log Analytics workspace customer ID");
const template = JSON.parse(execFileSync("az", [
  "bicep", "build", "--file",
  fileURLToPath(new URL("../infra/bicep/modules/sentinel-content.bicep", import.meta.url)),
  "--stdout",
], { encoding: "utf8" }));
const query = template.resources.find((resource) => resource.type === "Microsoft.SecurityInsights/alertRules").properties.query;
const token = JSON.parse(execFileSync("az", [
  "account", "get-access-token", "--resource", "https://api.loganalytics.io",
], { encoding: "utf8" })).accessToken;

async function execute(query, expectedMissingTable) {
  const response = await fetch(`https://api.loganalytics.io/v1/workspaces/${workspace}/query`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ query, timespan: "PT10M" }),
    signal: AbortSignal.timeout(60000),
  });
  const result = await response.json();
  assert.ok(response.ok, `KQL HTTP ${response.status}: ${JSON.stringify(result.error)}`);
  if (result.error) {
    assert.ok(expectedMissingTable, `Unexpected KQL error: ${JSON.stringify(result.error)}`);
    assert.equal(result.error.code, "PartialError");
    assert.ok(result.error.details?.length);
    for (const detail of result.error.details) {
      assert.equal(detail.innererror?.severityName, "Warning");
      assert.equal(detail.innererror.message, `'union' operator: Failed to resolve table expression named '${expectedMissingTable}'`);
    }
    console.log(`Expected fuzzy-union warning: ${expectedMissingTable} is absent; typed empty input supplies the schema.`);
  }
  const table = result.tables.find((table) => table.name === "PrimaryResult");
  assert.ok(table, "KQL did not return a result table");
  assert.deepEqual(table.columns.map((column) => column.name), ["TimeGenerated", "ruleName_s", "clientIP_s", "BlockCount"]);
  return table.rows;
}

await test("deployed analytics query executes with or without the diagnostics table", async () => {
  await execute(query, "AzureDiagnostics");
});

await test("missing diagnostics table validates and yields no false alerts", async () => {
  const missingTable = `LabRotMissingDiagnostics_${Date.now()}`;
  const missing = query.replace("AzureDiagnostics", missingTable);
  assert.deepEqual(await execute(missing, missingTable), []);
});

await test("diagnostics without WAF columns validate and yield no false alerts", async () => {
  const partial = query.replace("AzureDiagnostics", `(datatable(
    TimeGenerated:datetime, ResourceProvider:string, Category:string
  ) [datetime(2026-01-01), "MICROSOFT.CDN", "FrontDoorWebApplicationFirewallLog"])`);
  assert.deepEqual(await execute(partial), []);
});

await test("six blocks alert, five do not; allow events and different clients/time bins do not combine", async () => {
  const fixture = `(range i from 1 to 35 step 1
    | extend TimeGenerated = iff(i > 32, datetime(2026-01-01T00:06:00Z), datetime(2026-01-01T00:00:00Z)),
        ResourceProvider = "MICROSOFT.CDN", Category = "FrontDoorWebApplicationFirewallLog",
        action_s = iff(i between (12 .. 17), "Allow", "Block"),
        ruleName_s = case(i <= 6, "six-blocks", i <= 11, "five-blocks", i <= 17, "allows", i <= 23, "split-clients", i <= 29, "mixed-actions", "split-bins"),
        clientIP_s = iff(i between (21 .. 23), "192.0.2.2", "192.0.2.1")
    | extend action_s = iff(i between (27 .. 29), "Allow", action_s)
    | project TimeGenerated, ResourceProvider, Category, action_s, ruleName_s, clientIP_s)`;
  const rows = await execute(query.replace("AzureDiagnostics", fixture));
  assert.equal(rows.length, 1);
  assert.equal(rows[0][1], "six-blocks");
  assert.equal(rows[0][2], "192.0.2.1");
  assert.equal(rows[0][3], 6);
});
