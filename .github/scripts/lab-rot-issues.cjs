const { createHash } = require("node:crypto");

function normalizeFindings(findings) {
  return [...new Set(findings.split("\n").map((line) => {
    const warning = line.match(/(infra\/[^\s(]+\.bicep)\(\d+,\d+\).*Warning use-recent-api-versions: Use more recent API version for '([^']+)'\. '([^']+)'/);
    return warning
      ? `${warning[1]}: API age advisory: ${warning[2]}@${warning[3]}`
      : line.trim();
  }).filter(Boolean))].sort().join("\n");
}

function fingerprint(findings) {
  return createHash("sha256").update(normalizeFindings(findings)).digest("hex");
}

function reportedFindings(body = "") {
  const start = body.indexOf("### ");
  if (start === -1) return "";
  return body.slice(start).split(/\n---(?:\n|$)/)[0].trim();
}

async function syncIssue({ github, context, findings }) {
  if (!findings?.trim()) throw new Error("Cannot publish empty lab-rot findings");
  const { owner, repo } = context.repo;
  const hash = fingerprint(findings);
  const marker = `<!-- lab-rot-fingerprint:${hash} -->`;
  const issues = await github.paginate(github.rest.issues.listForRepo, {
    owner, repo, labels: "lab-rot", state: "all", per_page: 100,
  });
  const matching = issues.filter((issue) => !issue.pull_request && (
    issue.body?.includes(marker) ||
    fingerprint(reportedFindings(issue.body ?? "")) === hash
  ));
  const latestClosed = matching
    .filter((issue) => issue.state === "closed")
    .sort((a, b) => Date.parse(b.closed_at ?? "") - Date.parse(a.closed_at ?? "") || b.number - a.number)[0];
  const existing = matching.find((issue) => issue.state === "open") ??
    (latestClosed?.state_reason === "not_planned" ? latestClosed : undefined);
  if (existing) {
    console.log(`Unchanged findings already tracked or declined in #${existing.number} (${existing.state}); no new issue or comment.`);
    return existing.number;
  }

  try {
    await github.rest.issues.getLabel({ owner, repo, name: "lab-rot" });
  } catch (error) {
    if (error.status !== 404) throw error;
    await github.rest.issues.createLabel({
      owner, repo, name: "lab-rot", description: "Lab-rot watch findings", color: "FBCA04",
    });
  }

  const { data } = await github.rest.issues.create({
    owner,
    repo,
    title: "Lab rot watch: review findings",
    labels: ["lab-rot"],
    assignees: [owner],
    body: `Weekly static-analysis sweep flagged potential drift. **No live deployment was performed.**

API-age warnings are maintenance advisories, not evidence of retirement or a broken lab. Check provider support and learner impact before changing working APIs; do not downgrade diagnosticSettings solely to satisfy the age rule.

${findings}

---
- [ ] Triaged
- [ ] Action taken (fix, follow-up issue, or close as not-a-problem)

${marker}

_Auto-opened by [.github/workflows/lab-rot-watch.yml](https://github.com/${owner}/${repo}/blob/HEAD/.github/workflows/lab-rot-watch.yml)._`,
  });
  console.log(`Created lab-rot issue #${data.number}.`);
  return data.number;
}

module.exports = { normalizeFindings, fingerprint, syncIssue };
