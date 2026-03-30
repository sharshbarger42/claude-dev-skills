### Commit and Push

1. Stage changed files individually (`git add <file1> <file2> ...` — NOT `git add -A` or `git add .`)
2. Commit using the repo's conventional commit format from AGENTS.md. Use the appropriate type and scope for the change:
   - New feature implementation: `feat(#{index}): short description`
   - Bug fix: `fix(#{index}): short description`
   - PR review fixes: `fix(#{pr_index}): address PR review — {brief summary}`
   - CI fix: `fix(#{pr_index}): resolve CI {tool} failures`
   - **IMPORTANT:** Per AGENTS.md Rule 3 — NO Claude/AI/co-authored-by references in commit messages
3. Push the branch: `git push -u origin {branch_name}`
