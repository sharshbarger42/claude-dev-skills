### Labeling Issues

When creating a Gitea issue, apply both a **type** label and a **priority** label using one call:

```
mcp__gitea-workflow__label_issue
  owner: {owner}
  repo: {repo}
  index: {issue_index}
  type_label: "bug" | "enhancement" | "feature" | "chore" | "polish" | "contract" | "sub-issue" | "design"
  priority: "high" | "medium" | "low"
```

- **Type label** — pick one: `bug` (broken behavior, security vulnerability, correctness problem), `enhancement` (improvement to existing functionality), `feature` (new user-visible capability), `chore` (internal refactor, dep upgrade, no user-visible change), `polish` (visual/copy/styling tweak, no logic change), `contract` (cross-cutting interface/schema/API definition that blocks dependents), `sub-issue` (AI-sized implementation task scoped to a single code area), or `design` (spike, RFC, research, architecture decision — deliverable is a decision or doc, not shipped code)
- **Priority label** — pick one based on severity/impact: `high` (blocks users or other work, service down, or data at risk), `medium` (degraded functionality, normal queue), or `low` (cosmetic, nice to have)
- If any label doesn't exist in the repo, it's skipped silently
- Both parameters are optional — you can set just type or just priority
