### Labeling Issues

When creating a Gitea issue, apply both a **type** label and a **priority** label:

1. Call `mcp__gitea__list_repo_labels` to find label IDs for the repo
2. **Type label** — pick one: `bug` (broken behavior, security vulnerability, correctness problem), `enhancement` (improvement to existing functionality), or `feature` (new capability)
3. **Priority label** — pick one based on severity/impact: `priority: high` (blocks users or other work, service down, or data at risk), `priority: medium` (degraded functionality, normal queue), or `priority: low` (cosmetic, nice to have)
4. Call `mcp__gitea__add_issue_labels` with the new issue index and both label IDs
5. If any label doesn't exist in the repo, skip it silently
