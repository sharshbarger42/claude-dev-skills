# Pull Request Standards

Canonical standards for creating and reviewing Gitea pull requests across all super-werewolves repos. Read this before opening a PR or posting a review.

Related:
- [ISSUE_STANDARDS.md](./ISSUE_STANDARDS.md) — issue standards
- [pr-status-labels.md](./pr-status-labels.md) — PR workflow labels
- [review-checklists.md](./review-checklists.md) — detailed review passes

---

## Title Format

`{type}: {short imperative summary}`

- Mirror the commit convention: `feat:`, `fix:`, `enhance:`, `refactor:`, `docs:`, `test:`, `ci:`, `chore:`.
- Under 70 characters. Details go in the body, not the title.
- No trailing period. Present tense, imperative mood ("add", not "added" or "adds").
- If the PR resolves a single issue, include the number: `fix(#142): login fails with trailing whitespace`.

---

## Body Structure

```markdown
## Summary

{1–3 sentences: what changed and why. Focus on the "why" — the diff shows the "what".}

## Linked Issues

Closes #{N}
{or: Part of #{N} — {which part}}

## Changes

- {bullet: user-visible or architectural change}
- {bullet: notable implementation detail}

## Test Plan

- [ ] {specific, runnable verification step}
- [ ] {specific, runnable verification step}

## Notes

{Optional: deploy considerations, follow-up work, screenshots, rollback notes.}
```

Rules:
- **Summary** explains intent, not file list.
- **Linked Issues** uses `Closes #N` for auto-close on merge, `Part of #N` otherwise.
- **Test Plan** is a checklist the reviewer (or QA) can actually run. No "tested locally" hand-waves.
- Add screenshots or short clips for UI changes.

---

## Commit Standards

See the [repo-template pre-receive hook](https://git.home.superwerewolves.ninja/super-werewolves/repo-template) — these are enforced server-side.

- **No AI/Claude attribution.** No `Co-Authored-By: Claude`, no "Generated with Claude Code" trailers. The pre-receive hook and `.gitea/workflows/check-commits.yml` reject these.
- **Linear history.** Rebase onto the latest `origin/main` before pushing. No merge commits into the PR branch.
- **Conventional-commit subject.** `type(scope): summary` — match the PR title convention.
- **Reference the issue** in the commit body or subject: `fix(#142): ...` or a trailing `Refs: #142`.
- **Subject ≤ 72 chars**, body wrapped at ~80 chars.
- **One logical change per commit.** Squash fixups before pushing.
- **No secrets.** `.env`, credentials, tokens, private keys never land in a commit.

---

## Branching

- Always branch from the latest `origin/main`. Never from whatever happens to be checked out.
- Branch names: `{type}/{issue-number}-{short-slug}` — e.g., `feat/142-recipe-import`, `fix/87-login-whitespace`.
- Fresh branch per PR. If a PR is closed without merging, start a new branch for the follow-up — don't reuse.
- Work in a git worktree (`.claude/worktrees/{branch-name}`) so the main checkout stays clean.

---

## Labels

PR labels are managed by the `gitea-workflow` MCP server and the dev-workflow skills. Don't set them manually unless the skill isn't running.

| Label | Meaning | Applied by |
|-------|---------|------------|
| `pr: needs-review` | PR open, waiting for code review | `/do-issue` (on PR creation) |
| `pr: comments-pending` | Review posted with findings to address | `/review-pr` (when verdict has criticals/warnings) |
| `pr: awaiting-dev-verification` | Approved, awaiting dev deploy + smoke tests (dev-deploy repos only) | `/fix-pr`, `/review-pr` |
| `pr: ready-to-merge` | Approved and verified (or no dev deploy) | `/qa-pr`, `/review-pr`, `/fix-pr` |
| `pr: awaiting-prod-verification` | Merged, awaiting prod deploy checks | `/merge-prs` |

Swap via `mcp__gitea-workflow__set_pr_label` (accepts verdict `APPROVE` / `COMMENT` / `REQUEST_CHANGES`, or a direct label key). The tool removes the old label, picks the right new one based on the repo's deploy config, and skips silently if the label isn't present.

---

## Review Standards

Every PR gets a four-pass review via `/review-pr`. Findings are tiered by severity.

### Passes

1. **Security & Correctness** — injection, auth/authz, secrets, logic errors, error handling, data validation, race conditions, resource leaks.
2. **Architecture & Design** — pattern adherence, separation of concerns, naming, over-engineering, worthwhile deduplication. Do NOT flag cleanups/refactors/docs as "scope creep."
3. **Standards Compliance** — repo-specific rules (AGENTS.md), commit format (only flag wrong issue numbers, not style), file placement, hardcoded values.
4. **Edge Cases & Robustness** — input validation, boundary checks, null/empty handling, external-call failure modes, timeouts, backwards compatibility.

See [review-checklists.md](./review-checklists.md) for the full checklist per pass.

### Severity Tiers

| Tier | Meaning | Blocks approval? |
|------|---------|-------------------|
| **Critical** | Security vulnerability, data loss, breaks prod, secret leak | Yes |
| **Important** | Correctness bug, architectural violation, missing test for risky path | Yes |
| **Contextual** | Style, minor clarity, optional improvement | No — suggest, don't block |

### Verdicts

| Verdict | When |
|---------|------|
| `APPROVE` | No critical or important findings; contextual-only is fine |
| `COMMENT` | Findings exist but the author may choose how to address |
| `REQUEST_CHANGES` | Any critical or important finding that must be resolved |

### Reviewer Rules

- **Verify claims before making them.** Check the actual base branch, check paths exist, check patterns are documented. No assertions from assumption.
- **Don't flag additive improvements as out-of-scope.** Cleanups, renames, small doc updates are welcome in any PR. Only flag if a commit references the wrong issue.
- **Don't re-flag style** the repo doesn't enforce.

---

## Author Workflow

1. Branch from `origin/main` into a worktree.
2. Implement against the issue's acceptance criteria.
3. Rebase on latest `origin/main` before opening the PR.
4. Push and open the PR. `/do-issue` applies `pr: needs-review`.
5. `/review-pr` runs the four-pass review and sets a verdict label.
6. `/fix-pr` addresses comments, pushes, and moves the label forward.
7. `/qa-pr` verifies on dev (if the repo has a dev deploy).
8. `/merge-prs` merges when `pr: ready-to-merge` and runs post-merge health checks.

---

## Checklist Before Opening

- [ ] Branched from latest `origin/main` (not a stale local main)
- [ ] Rebased, linear history, no merge commits into the branch
- [ ] Commit messages follow conventional format, reference the issue, no AI attribution
- [ ] Title matches `{type}: {summary}` and is under 70 chars
- [ ] Body has Summary, Linked Issues, Changes, Test Plan
- [ ] No secrets, `.env`, or credentials in the diff
- [ ] Screenshots/clips added for UI changes
- [ ] `pr: needs-review` label applied (done by `/do-issue` automatically)
