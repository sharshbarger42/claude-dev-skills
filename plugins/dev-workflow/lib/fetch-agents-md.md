### Fetch repo AGENTS.md

Use `mcp__gitea__get_file_contents` to fetch `AGENTS.md` from the repo's default branch. Get the default branch name from the issue/PR metadata (`repository.default_branch`) — do NOT hardcode `master` or `main`.

If AGENTS.md doesn't exist, note that no repo-specific coding standards were found and proceed without it.
