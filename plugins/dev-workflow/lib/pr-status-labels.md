### PR Status Labels

All repos use these `pr:` labels to track pull request workflow state in the Gitea UI:

| Label | Meaning | Applied by |
|-------|---------|------------|
| `pr: needs-review` | PR is open and waiting for code review | `/do-issue` (on PR creation) |
| `pr: comments-pending` | Review posted with findings that need to be addressed | `/review-pr` (when verdict has criticals/warnings) |
| `pr: awaiting-dev-verification` | Approved, awaiting dev deploy + smoke tests (only for repos with dev deploy config) | `/fix-pr`, `/review-pr` (when approved, repo has dev deploy) |
| `pr: ready-to-merge` | Approved, verified (or no dev deploy), good to go | `/qa-pr` (when QA passes), `/review-pr` or `/fix-pr` (when approved, repo has no dev deploy) |
| `pr: awaiting-prod-verification` | Merged, awaiting prod deploy health checks | `/merge-prs` (after merge, repo has prod deploy) |

### Setting PR status labels

Use the `gitea-workflow` MCP server — it handles label ID lookups, old label removal, deploy-config awareness, and the swap in a single call:

- **After review:** `mcp__gitea-workflow__set_pr_label` with `verdict` = `"APPROVE"`, `"COMMENT"`, or `"REQUEST_CHANGES"`. The tool automatically picks the correct label based on the verdict and the repo's deploy config.
- **Direct label set:** Pass a label key as `verdict`: `"needs-review"`, `"comments-pending"`, `"awaiting-dev-verification"`, `"ready-to-merge"`, `"awaiting-prod-verification"`.
- **After review with post:** `mcp__gitea-workflow__post_review` posts the review AND sets the label in one call.
- **After merge:** `mcp__gitea-workflow__merge_pr` merges AND sets the post-merge label.

If the target label doesn't exist in the repo, the tool skips silently — labels are informational and should not block the skill's main workflow.
