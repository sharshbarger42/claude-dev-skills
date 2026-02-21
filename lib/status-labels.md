### Status Labels

All repos use these `status:` labels to track issue lifecycle:

| Label | Meaning |
|-------|---------|
| `status: backlog` | Not yet started |
| `status: in-progress` | Actively being worked on |
| `status: in-review` | PR open, awaiting review/merge |
| `status: done` | Completed |

### Swapping status labels

Label IDs vary by repo — you cannot hardcode them. To transition an issue's status:

1. **Get the label ID by name:** Fetch the issue's current labels from the issue metadata, or use `mcp__gitea__list_repo_labels` to look up label IDs by name for the repo.
2. **Remove the old status label:** Use `mcp__gitea__remove_issue_label` with the label ID of the current `status:` label.
3. **Add the new status label:** Use `mcp__gitea__add_issue_labels` with the label ID of the desired `status:` label.

Always remove before adding to avoid an issue having two `status:` labels simultaneously.
