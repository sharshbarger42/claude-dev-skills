### Deploy-Aware PR Label Selection

The `gitea-workflow` MCP server handles deploy-aware label selection automatically. When you call `mcp__gitea-workflow__set_pr_label` with a verdict, or use `mcp__gitea-workflow__post_review` / `mcp__gitea-workflow__merge_pr`, the correct label is chosen based on the repo's deploy configuration.

You do **not** need to check deploy config manually. The MCP server reads `~/.config/development-skills/deploy-config.md` on startup and applies these rules internally:

**After review approval or fix completion (pre-merge):**
- Repo **has** dev deploy config → `pr: awaiting-dev-verification`
- Repo has **no** dev deploy config → `pr: ready-to-merge`

**After merge (post-merge):**
- Repo **has** prod deploy config → `pr: awaiting-prod-verification`
- Repo has **no** prod deploy config → no label needed (PR is done)

**After prod verification passes:** Remove `pr: awaiting-prod-verification` manually using `mcp__gitea__remove_issue_label` or by calling `mcp__gitea-workflow__set_pr_label` with `verdict: "ready-to-merge"`.
