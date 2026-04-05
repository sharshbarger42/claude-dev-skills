### Labeling Issues

When creating a Gitea issue, apply both a **type** label and a **priority** label using one call:

```
mcp__gitea-workflow__label_issue
  owner: {owner}
  repo: {repo}
  index: {issue_index}
  type_label: "bug" | "enhancement" | "feature"
  priority: "high" | "medium" | "low"
```

- **Type label** — pick one: `bug` (broken behavior, security vulnerability, correctness problem), `enhancement` (improvement to existing functionality), or `feature` (new capability)
- **Priority label** — pick one based on severity/impact: `high` (blocks users or other work, service down, or data at risk), `medium` (degraded functionality, normal queue), or `low` (cosmetic, nice to have)
- If any label doesn't exist in the repo, it's skipped silently
- Both parameters are optional — you can set just type or just priority
