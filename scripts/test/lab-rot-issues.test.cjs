const { test } = require("node:test");
const assert = require("node:assert/strict");
const { fingerprint, syncIssue } = require("../../.github/scripts/lab-rot-issues.cjs");

function findings({ days = 976, path = "/home/runner/work/repo/repo", line = 29, accepted = "2025-01-01", api = "2024-03-01" } = {}) {
  return `### Stale Bicep API versions\n\n\`\`\`\n${path}/infra/bicep/modules/origin-webapp.bicep(${line},49) : Warning use-recent-api-versions: Use more recent API version for 'Microsoft.App/managedEnvironments'. '${api}' is ${days} days old, should be no more than 730 days old, or the most recent. Acceptable versions: ${accepted} [https://aka.ms/bicep/linter-diagnostics#use-recent-api-versions]\n\`\`\``;
}

function client(issues) {
  const created = [];
  return {
    created,
    github: {
      paginate: async (_method, options) => {
        assert.equal(options.state, "all");
        assert.equal(options.per_page, 100);
        assert.equal(options.labels, "lab-rot");
        return issues;
      },
      rest: {
        issues: {
          listForRepo: () => {},
          getLabel: async () => ({ data: { name: "lab-rot" } }),
          createLabel: async () => { throw new Error("Existing labels must not be recreated"); },
          create: async (issue) => {
            created.push(issue);
            return { data: { number: 42 } };
          },
        },
      },
    },
    context: { repo: { owner: "owner", repo: "repo" } },
  };
}

test("API age identity ignores age, runner paths, source positions and suggested versions", () => {
  assert.equal(fingerprint(findings()), fingerprint(findings({
    days: 983, path: "/different/workspace", line: 35, accepted: "2026-07-01, 2025-01-01",
  })));
});

test("identity preserves API, resource and non-age finding changes", () => {
  assert.notEqual(fingerprint(findings()), fingerprint(findings({ api: "2025-01-01" })));
  assert.notEqual(fingerprint(findings()), fingerprint(findings().replace("managedEnvironments", "containerApps")));
  assert.notEqual(fingerprint(findings()), fingerprint(`${findings()}\n### Broken external links\nhttps://example.com/broken`));
});

test("normalization is insensitive to ordering and repeated diagnostics", () => {
  assert.equal(fingerprint("a\nb\na\n\n"), fingerprint("b\na"));
});

for (const state of ["open", "closed"]) {
  test(`legacy ${state} reports suppress weekly duplicates when open or explicitly declined`, async () => {
    const mock = client([{
      number: 18,
      state,
      state_reason: state === "closed" ? "not_planned" : null,
      body: `Weekly report\n\n${findings()}\n\n---\n- [x] Triaged\n<!-- lab-rot-fingerprint:old-hash -->`,
    }]);
    assert.equal(await syncIssue({ ...mock, findings: findings({ days: 1000 }) }), 18);
    assert.equal(mock.created.length, 0);
  });
}

test("marker retains identity after a maintainer edits the report", async () => {
  const mock = client([{ number: 18, state: "closed", state_reason: "not_planned", body: `Triaged.\n<!-- lab-rot-fingerprint:${fingerprint(findings())} -->` }]);
  assert.equal(await syncIssue({ ...mock, findings: findings() }), 18);
  assert.equal(mock.created.length, 0);
});

test("genuinely new findings create an issue with stable marker and advisory context", async () => {
  const mock = client([]);
  assert.equal(await syncIssue({ ...mock, findings: findings() }), 42);
  assert.equal(mock.created.length, 1);
  assert.ok(mock.created[0].body.includes(`lab-rot-fingerprint:${fingerprint(findings())}`));
  assert.match(mock.created[0].body, /not evidence of retirement/);
});

test("a completed fix does not suppress a recurrence", async () => {
  const mock = client([{ number: 18, state: "closed", state_reason: "completed", body: findings() }]);
  assert.equal(await syncIssue({ ...mock, findings: findings() }), 42);
  assert.equal(mock.created.length, 1);
});

test("a later completed tracker supersedes an older declined duplicate", async () => {
  const body = findings();
  const mock = client([
    { number: 18, state: "closed", state_reason: "not_planned", closed_at: "2026-10-01T00:00:00Z", body },
    { number: 42, state: "closed", state_reason: "completed", closed_at: "2026-11-02T00:00:00Z", body },
  ]);
  assert.equal(await syncIssue({ ...mock, findings: body }), 42);
  assert.equal(mock.created.length, 1);
});

test("the newest declined tracker suppresses older completed trackers regardless of API ordering", async () => {
  const body = findings();
  const mock = client([
    { number: 42, state: "closed", state_reason: "not_planned", closed_at: "2026-11-02T00:00:00Z", body },
    { number: 18, state: "closed", state_reason: "completed", closed_at: "2026-10-01T00:00:00Z", body },
  ]);
  assert.equal(await syncIssue({ ...mock, findings: body }), 42);
  assert.equal(mock.created.length, 0);
});

test("the first report creates the watcher label if missing", async () => {
  const mock = client([]);
  mock.github.rest.issues.getLabel = async () => { throw Object.assign(new Error("Not Found"), { status: 404 }); };
  let createdLabel;
  mock.github.rest.issues.createLabel = async (label) => { createdLabel = label; };
  await syncIssue({ ...mock, findings: findings() });
  assert.equal(createdLabel.name, "lab-rot");
  assert.equal(createdLabel.color, "FBCA04");
  assert.equal(mock.created.length, 1);
});

test("label permission errors do not silently create an unlabelled issue", async () => {
  const mock = client([]);
  mock.github.rest.issues.getLabel = async () => { throw Object.assign(new Error("Forbidden"), { status: 403 }); };
  await assert.rejects(syncIssue({ ...mock, findings: findings() }), /Forbidden/);
  assert.equal(mock.created.length, 0);
});

test("pull requests are not treated as triaged issues", async () => {
  const mock = client([{ number: 18, pull_request: {}, body: findings() }]);
  await syncIssue({ ...mock, findings: findings() });
  assert.equal(mock.created.length, 1);
});

test("empty findings and GitHub failures are explicit errors", async () => {
  const mock = client([]);
  await assert.rejects(syncIssue({ ...mock, findings: "" }), /empty/);
  mock.github.paginate = async () => { throw new Error("GitHub unavailable"); };
  await assert.rejects(syncIssue({ ...mock, findings: findings() }), /GitHub unavailable/);
});
