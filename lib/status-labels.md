### Status Labels

All repos use these `status:` labels to track issue lifecycle:

| Label | Meaning |
|-------|---------|
| `status: backlog` | Not yet started |
| `status: in-progress` | Actively being worked on |
| `status: ready-to-test` | Fix pushed, awaiting QA verification |
| `status: in-review` | PR open, awaiting review/merge |
| `status: done` | Completed |

### Swapping status labels

Use `mcp__gitea-workflow__set_issue_status` with `status` set to one of: `"backlog"`, `"in-progress"`, `"ready-to-test"`, `"in-review"`, `"done"`.

The tool handles label ID lookups and removes any existing `status:` label before adding the new one. No need to call `list_repo_labels` or manage label IDs manually.

### Blocking Labels

These non-status labels prevent agents from auto-picking issues:

| Label | Meaning |
|-------|---------|
| `decision-needed` | A human decision is required before implementation can proceed. The issue comments contain the open question. Agents must not implement without the decision being resolved first. |

When an agent encounters an issue with `decision-needed`:
- **`/do-issue`**: Read the issue comments, present the pending decision to the user, and ask how to proceed before any implementation.
- **`/triage-issues`**: Show these issues in a separate "Awaiting Decision" section, not in the recommended list.
- **`/do-the-thing`**: Exclude from auto-recommendations unless the user explicitly requests them.
