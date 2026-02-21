---
name: review-pr
description: Review a Gitea PR using code-review-agent. Fetches diff, runs parallel security + architecture review, posts comments.
---

# PR Review Skill

Review a Gitea pull request and post the review as `code-review-agent`.

**Input:** PR reference as the skill argument. Accepted formats:
- Shorthand: `food-automation#32`
- Owner/repo: `super-werewolves/food-automation#32`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/pulls/32`

## Step 1: Read token

Read the code-review-agent token:
!`cat $HOME/.config/code-review-agent/token 2>/dev/null || echo "MISSING"`

If the token is `MISSING`, stop and tell the user:
> code-review-agent token not found. Create it at `~/.config/code-review-agent/token` (chmod 600).

Store the token value for use in Step 7.

## Step 2: Parse the PR reference

Extract `owner`, `repo`, and PR `index` from the argument.

### Repo resolution

!`cat $HOME/gitea-repos/development-skills/lib/resolve-repo.md`

## Step 3: Fetch PR metadata

Use `mcp__gitea__get_pull_request_by_index` with the parsed `owner`, `repo`, and `index` to get:
- PR title
- PR body/description
- Base and head branches

If the PR is not found, report the error and stop.

## Step 4: Fetch PR diff

Use `mcp__gitea__get_pull_request_diff` with the same `owner`, `repo`, and `index`.

If the diff is larger than 100KB, note this and focus the review on the largest changed files. Summarize smaller changes.

## Step 5: Read repo AGENTS.md

Use `mcp__gitea__get_file_content` to fetch `AGENTS.md` from the repo's default branch. Get the default branch name from the PR metadata (`base.repo.default_branch`) — do NOT hardcode `master` or `main`.

If AGENTS.md doesn't exist, note that no repo-specific coding standards were found and proceed without it.

## Step 6: Launch review subagents

Launch **two** Task subagents **in parallel**:

### Subagent 1: Security & Bug Review (`vern:paranoid`)

Prompt:
```
You are reviewing a pull request for security issues, bugs, and correctness problems.

## PR: {title}
{pr_body}

## Repository Coding Standards
{agents_md_content OR "No AGENTS.md found for this repository."}

## Diff
{diff}

Review this PR focusing on:
- Security vulnerabilities (injection, auth issues, secrets exposure, unsafe operations)
- Bugs and logic errors
- Error handling gaps
- Data validation issues
- Race conditions or concurrency problems

Produce your review in this exact format:

## Summary
[1-2 sentence overall security/correctness assessment]

## Verdict
APPROVE | REQUEST_CHANGES | COMMENT

## Inline Comments
- **path/to/file.py:LINE_NUMBER** — [specific issue with this line]

## General Comments
- [broader observations not tied to a specific line]

IMPORTANT: For inline comments, the LINE_NUMBER must be the line number within the diff (the new_position — i.e., the line number in the new version of the file as shown in the diff's @@ hunk headers). Only comment on lines that appear in the diff.
```

### Subagent 2: Architecture & Design Review (`vern:architect`)

Prompt:
```
You are reviewing a pull request for architecture, design, and code quality.

## PR: {title}
{pr_body}

## Repository Coding Standards
{agents_md_content OR "No AGENTS.md found for this repository."}

## Diff
{diff}

Review this PR focusing on:
- Architecture and design patterns
- Code organization and separation of concerns
- Naming and readability
- Compliance with repo coding standards (from AGENTS.md)
- Unnecessary complexity or over-engineering
- Missing tests or documentation where needed

Produce your review in this exact format:

## Summary
[1-2 sentence overall architecture/design assessment]

## Verdict
APPROVE | REQUEST_CHANGES | COMMENT

## Inline Comments
- **path/to/file.py:LINE_NUMBER** — [specific issue with this line]

## General Comments
- [broader observations not tied to a specific line]

IMPORTANT: For inline comments, the LINE_NUMBER must be the line number within the diff (the new_position — i.e., the line number in the new version of the file as shown in the diff's @@ hunk headers). Only comment on lines that appear in the diff.
```

## Step 7: Synthesize and post review

Combine the outputs from both subagents into a single review.

### Build the review body

Format the combined review as:

```
## Code Review — {PR title}

### Security & Correctness
{paranoid subagent summary}

### Architecture & Design
{architect subagent summary}

### Verdict
- Security: {paranoid verdict}
- Architecture: {architect verdict}

### Details

{All general comments from both subagents, grouped by topic}
```

### Build the inline comments array

Parse all `**path/to/file.py:LINE** — comment` entries from both subagents. For each:
- Extract `path` (the file path)
- Extract `new_position` (the line number)
- Extract the comment body
- Tag with `[Security]` or `[Architecture]` prefix based on which subagent produced it

Build a JSON array of comment objects:
```json
[
  {
    "path": "path/to/file.py",
    "body": "[Security] comment text here",
    "new_position": 42
  }
]
```

### Post the review via curl

Use the Bash tool to post the review using the code-review-agent token. Read the Gitea API URL from the infrastructure config:

!`cat $HOME/gitea-repos/development-skills/config/infrastructure.md`

```bash
curl -s -X POST \
  -H "Authorization: token {TOKEN}" \
  -H "Content-Type: application/json" \
  "{GITEA_API_URL}/repos/{owner}/{repo}/pulls/{index}/reviews" \
  -d '{
    "body": "REVIEW_BODY_HERE",
    "event": "COMMENT",
    "comments": [INLINE_COMMENTS_ARRAY]
  }'
```

**Important:**
- Always use `"event": "COMMENT"` — never APPROVE or REQUEST_CHANGES (the agent recommends but doesn't gate merges)
- If there are no inline comments, omit the `comments` field or pass an empty array
- Properly escape the JSON body (use a heredoc or write to a temp file if needed)
- Use the Gitea API URL from `config/infrastructure.md` (the `Gitea API URL` row)
- **CRITICAL: Inline comment field names differ between the MCP tool and the REST API.** The Gitea REST API expects `new_position` and `old_position`. Do NOT use `new_line_num` / `old_line_num` (those are MCP tool parameter names only). Using the wrong field name causes all comments to silently collapse to position 0.

### Report results

After posting, tell the user:
1. The review was posted successfully (or report any errors)
2. A brief summary of findings
3. How many inline comments were posted
4. The verdicts from each subagent
