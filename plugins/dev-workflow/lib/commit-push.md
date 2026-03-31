### Commit and Push

1. Stage changed files individually (`git add <file1> <file2> ...` — NOT `git add -A` or `git add .`)
2. Commit using the repo's conventional commit format from AGENTS.md. Use the appropriate type and scope for the change:
   - New feature implementation: `feat(#{index}): short description`
   - Bug fix: `fix(#{index}): short description`
   - PR review fixes: `fix(#{pr_index}): address PR review — {brief summary}`
   - CI fix: `fix(#{pr_index}): resolve CI {tool} failures`
   - **IMPORTANT:** Per AGENTS.md Rule 3 — NO Claude/AI/co-authored-by references in commit messages
3. Push the branch: `git push -u origin HEAD` (pushes the current branch to its upstream)

### Clean History Rules

The PR branch must have a clean, meaningful commit history before pushing. Follow these rules:

- **No fix-up commits.** If you're fixing a lint error, test failure, or typo introduced by a previous commit, fold the fix into the original commit — don't create a new "fix lint" or "fix CI" commit. If the target is the most recent commit (HEAD), use `git commit --amend --no-edit`. If the target is an earlier commit, use `git commit --fixup {sha}` followed by `GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash $(git merge-base HEAD {base_branch})`. If this is the **first commit** on the branch (nothing to amend yet), use a normal `git commit`.
- **No WIP commits.** Every commit on the branch should be a standalone, meaningful unit of work with a clear message explaining what changed and why.
- **Squash iterative fixes.** When you need to fold a change into an earlier commit (e.g., after review feedback), use `git commit --fixup {sha}` to create a targeted fixup commit, then squash with `GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash $(git merge-base HEAD {base_branch})` and force-push with `--force-with-lease`. Use `git log --oneline {base_branch}..HEAD` to find the correct SHA to target. If rebase encounters a conflict, `git rebase --abort` and fall back to manual amend.
- **Evaluate before pushing.** Run `git log --oneline {base_branch}..HEAD` (where `{base_branch}` is the PR's target branch — do NOT hardcode `main`) and check: does every commit represent a meaningful change? Are there any "address review", "fix lint", "wip" messages? If so, clean up first.
