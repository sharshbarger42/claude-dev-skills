### PR Status Labels

All repos use these `pr:` labels to track pull request workflow state in the Gitea UI:

| Label | Meaning | Applied by |
|-------|---------|------------|
| `pr: needs-review` | PR is open and waiting for code review | `/do-issue` (on PR creation) |
| `pr: comments-pending` | Review posted with findings that need to be addressed | `/review-pr` (when verdict has criticals/warnings) |
| `pr: awaiting-dev-verification` | Approved, awaiting dev deploy + smoke tests (only for repos with dev deploy config) | `/fix-pr`, `/review-pr` (when approved, repo has dev deploy) |
| `pr: ready-to-merge` | Approved, verified (or no dev deploy), good to go | `/qa-pr` (when QA passes), `/review-pr` or `/fix-pr` (when approved, repo has no dev deploy) |
| `pr: awaiting-prod-verification` | Merged, awaiting prod deploy health checks | `/merge-prs` (after merge, repo has prod deploy) |

**Note:** For repos without a dev deploy config, skip `pr: awaiting-dev-verification` and set `pr: ready-to-merge` directly. See `deploy-aware-label.md` for the config-checking logic.

### Swapping PR status labels

PR labels are applied to the PR's **issue index** (in Gitea, PRs are issues). The procedure is the same as issue status labels:

1. **Get the label ID by name:** Use `mcp__gitea__list_repo_labels` to look up label IDs by name. Cache the result per repo if processing multiple PRs.
2. **Remove any existing `pr:` label:** Check the PR's current labels for any label whose name starts with `pr:`. Remove each one using `mcp__gitea__remove_issue_label` with the PR's index.
3. **Add the new `pr:` label:** Use `mcp__gitea__add_issue_labels` with the PR's index and the target label ID.

Always remove before adding to avoid a PR having two `pr:` labels simultaneously.

If the target label doesn't exist in the repo, skip silently — don't error. The labels are informational and should not block the skill's main workflow.

### Label creation

Labels must exist in each repo before they can be applied. If `/list-prs` or any skill finds that `pr:` labels don't exist in a repo, it should note this in its output but not create them automatically. The user can create them manually or via a setup script.
